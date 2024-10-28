locals {
  cloud_run_backends = {
    for service in keys(var.services) : service => module.serverless_negs[service].backend
  }
  cloud_run_backend_paths = {
    for service in keys(var.services) : service => {
      id = module.lb.backend_services[service].id
    }
  }
  bucket_backend_paths = {
    for bucket in keys(var.buckets) : bucket => {
      id = module.buckets[bucket].id
    }
  }
  cloud_run_default_error_response_rules = {
    for service in keys(var.services) : service => {
      default_custom_error_response_policy  = var.services[service].default_custom_error_response_policy
    }
  }
  bucket_default_error_response_rules = {
    for bucket in keys(var.buckets) : bucket => {
      default_custom_error_response_policy  = var.services[service].default_custom_error_response_policy
    }
  }
  default_error_response_rule = coalesce(var.default_custom_error_response_policy.error_response_rule, {})
  backend_paths               = merge(local.cloud_run_backend_paths, local.bucket_backend_paths)
  default_error_response_rules = merge(local.cloud_run_default_error_response_rules, local.bucket_default_error_response_rules)
  url_map_name                = var.url_map_name == "" ? "${var.name_prefix}-lb" : var.url_map_name
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
  for_each           = var.services
  source             = "github.com/brandlive1941/terraform-module-backend-serverless?ref=v1.0.1"
  project_id         = var.project_id
  name               = coalesce(each.value.backend["name"], each.key)
  cloud_run_services = each.value["cloud_run_regions"]
  enable_cdn         = each.value.backend["enable_cdn"]
  iap_config         = each.value.backend["iap_config"]
  log_config         = each.value.backend["log_config"]
}

# Backend Bucket Services
module "buckets" {
  for_each     = var.buckets
  source       = "github.com/brandlive1941/terraform-module-backend-bucket?ref=v1.0.4"
  project_id   = var.project_id
  name         = each.value["name"]
  location     = each.value["location"]
  service_name = each.value["service_name"]
  enable_cdn   = each.value.backend["enable_cdn"]
  cdn_policy   = each.value.backend["cdn_policy"]
  cors_policy  = each.value.backend["cors_policy"]
  iap_config   = each.value.backend["iap_config"]
  log_config   = each.value.backend["log_config"]
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

resource "google_compute_target_https_proxy" "default" {
  count           = var.enable_ssl ? 1 : 0
  name            = "${var.name_prefix}-https-proxy"
  url_map         = google_compute_url_map.urlmap.self_link
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

  default_custom_error_response_policy {
    error_response_rule {
      match_response_codes   = local.default_error_response_rule["match_response_codes"]
      path                   = local.default_error_response_rule["path"]
      override_response_code = local.default_error_response_rule["override_response_code"]
    }
    error_service = var.default_custom_error_response_policy["error_service"]
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
      default_custom_error_response_policy {
        dynamic "error_response_rule" {
          for_each = local.default_error_response_rules[path_matcher.key].default_custom_error_response_policy.error_response_rules
          content {
            match_response_codes   = error_response_rule.value.match_response_codes
            path                   = error_response_rule.value.path
            override_response_code = error_response_rule.value.override_response_code
          }
        }
        error_service = local.default_error_response_rules[path_matcher.key].default_custom_error_response_policy.error_service
      }
    }
  }
}
