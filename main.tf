locals {
  cloud_run_backends = {
    for service in keys(var.services) : service => module.serverless_negs[service].backend
  }
  cloud_run_backend_paths = {
    for service in keys(var.services) : service => {
      id = module.lb.backend_services[service].id
    }
  }
  cloud_run_default_custom_error_responses = {
    for service in keys(var.services) : service => {
      custom_error_responses = module.serverless_negs[service].default_custom_error_response_policy.custom_error_responses 
      error_service         = module.serverless_negs[service].default_custom_error_response_policy.error_service
    }
  }
  bucket_backend_paths = {
    for bucket in keys(var.buckets) : bucket => {
      id = module.buckets[bucket].id
    }
  }
  bucket_default_custom_error_responses = {
    for bucket in keys(var.buckets) : bucket => {
      custom_error_responses = module.buckets[bucket].default_custom_error_response_policy.custom_error_responses
      error_service          = module.buckets[bucket].default_custom_error_response_policy.error_service
    }
  }
  backend_paths          = merge(local.cloud_run_backend_paths, local.bucket_backend_paths)
  custom_error_responses = merge(local.cloud_run_default_custom_error_responses, local.bucket_default_custom_error_responses)
  url_map_name           = var.url_map_name == "" ? "${var.name_prefix}-lb" : var.url_map_name
}

# Global IP
data "google_compute_global_address" "default" {
  name = var.static_ip_name
}

data "google_certificate_manager_certificate_map" "default" {
  name = var.certificate_map
}

# Backend Serverless Network Endpoint Groups
module "serverless_negs" {
  for_each                             = var.services
  source                               = "github.com/brandlive1941/terraform-module-backend-serverless?ref=v1.1.1"
  project_id                           = var.project_id
  name                                 = coalesce(each.value.backend["name"], each.key)
  cloud_run_services                   = each.value["cloud_run_regions"]
  enable_cdn                           = each.value.backend["enable_cdn"]
  default_custom_error_response_policy = each.value.backend["default_custom_error_response_policy"]
  iap_config                           = each.value.backend["iap_config"]
  log_config                           = each.value.backend["log_config"]
}

# Backend Bucket Services
module "buckets" {
  for_each                             = var.buckets
  source                               = "github.com/brandlive1941/terraform-module-backend-bucket?ref=v1.2.0"
  #source                               = "github.com/brandlive1941/terraform-module-backend-bucket?ref=bdev-437-fix"
  project_id                           = var.project_id
  name                                 = each.value["name"]
  location                             = each.value["location"]
  service_name                         = each.value["service_name"]
  enable_cdn                           = each.value.backend["enable_cdn"]
  cdn_policy                           = each.value.backend["cdn_policy"]
  custom_response_headers              = each.value.backend["custom_response_headers"]
  cors_policy                          = each.value.backend["cors_policy"]
  iap_config                           = each.value.backend["iap_config"]
  log_config                           = each.value.backend["log_config"]
}

# Load Balancer
module "lb" {
  source                = "github.com/brandlive1941/terraform-module-gcp-serverless-negs?ref=v1.0.1"
  project               = var.project_id
  name                  = var.name_prefix
  address               = data.google_compute_global_address.default.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backends              = local.cloud_run_backends
  url_map               = google_compute_url_map.urlmap.self_link
  create_url_map        = false
  certificate_map       = var.certificate_map
  create_address        = var.create_address
}

resource "google_compute_global_forwarding_rule" "https" {
  provider              = google-beta
  project               = var.project_id
  count                 = var.enable_ssl ? 1 : 0
  name                  = "${var.name_prefix}-https-forwarding-rule"
  target                = google_compute_target_https_proxy.default[0].self_link
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = data.google_compute_global_address.default.address
  port_range            = var.port_range
  labels                = var.custom_labels_https_fwd_rule
}

# SSL Policy for the load balancer
resource "google_compute_ssl_policy" "tls12-ssl-policy" {
  name            = "${var.project_id}-tls12-ssl-policy"
  profile         = "MODERN"  # Use MODERN for strong security settings.
  min_tls_version = "TLS_1_2" # Only allow TLS 1.2 and above.

  description = "SSL policy to enforce TLS 1.2 and disable TLS 1.0 and 1.1"
}

resource "google_compute_target_https_proxy" "default" {
  count           = var.enable_ssl ? 1 : 0
  name            = "${var.name_prefix}-https-proxy"
  url_map         = google_compute_url_map.urlmap.self_link
  ssl_policy      = google_compute_ssl_policy.tls12-ssl-policy.self_link
  certificate_map = "//certificatemanager.googleapis.com/${data.google_certificate_manager_certificate_map.default.id}"
}

# URL Map
resource "google_compute_url_map" "urlmap" {
  provider    = google-beta
  project     = var.project_id
  name        = local.url_map_name
  description = "URL map for Loadbalancer"
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }

  dynamic "host_rule" {
    for_each = merge(var.services, var.buckets)
    content {
      hosts        = host_rule.value.hosts
      path_matcher = host_rule.key
    }
  }
  dynamic "path_matcher" {
    for_each = merge(var.services, var.buckets)
    content {
      name            = path_matcher.key
      default_service = local.backend_paths[path_matcher.key].id
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules
        content {
          paths   = path_rule.value["paths"]
          service = local.backend_paths[path_matcher.key].id
          dynamic "url_redirect" {
            for_each = path_rule.value.url_redirect
            content {
              host_redirect          = path_rule.value.host_redirect
              https_redirect         = path_rule.value.https_redirect
              path_redirect          = path_rule.value.path_redirect
              redirect_response_code = path_rule.value.redirect_response_code
              strip_query            = path_rule.value.strip_query
            }
          }
        }
      }
      dynamic "default_custom_error_response_policy" {
        for_each = coalesce(local.custom_error_responses[path_matcher.key].custom_error_responses, [])
        content {
            match_response_codes   = default_custom_error_response_policy.value.match_response_codes
            path                   = default_custom_error_response_policy.value.path
            override_response_code = default_custom_error_response_policy.value.override_response_code
        }
        error_service = local.custom_error_responses[path_matcher.key].error_service
      }
    }
  }
  depends_on = [module.buckets, module.lb.backend_services]
}
