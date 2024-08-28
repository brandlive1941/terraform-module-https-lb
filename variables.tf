variable "project_id" {
  type        = string
  description = "GCP Project ID where the loadbalancer will be created"
}

variable "region" {
  type        = string
  description = "GCP region where the loadbalancer will be created"
}

variable "environment" {
  type        = string
  description = "The application environment"
}

variable "static_ip_name" {
  type        = string
  description = "Name of the external-ip. the name must be 1-63 characters long and match the regular expression [a-z]([-a-z0-9]*[a-z0-9])?"
}

variable "name_prefix" {
  type        = string
  description = "Prefix-name used for lb proxy and forwarding rule"
}

variable "create_address" {
  type        = bool
  default     = true
  description = "Set to false to skip the creation of the load balancer"
}

variable "url_map" {
  type        = string
  description = "Name of the URL Map"
  default     = null
}

variable "custom_labels_https_fwd_rule" {
  type        = map(string)
  default     = {}
  description = "A map of custom labels to apply to the resources. The key is the label name and the value is the label value."
}

variable "ssl_cert_name" {
  type        = string
  default     = "(Optional) Creates a unique name beginning with the specified prefix."
  description = "SSL certificate name"
}

variable "certificate_map" {
  type        = string
  description = "The resource URL for the Certificate Map"
}

variable "port_range" {
  type        = number
  default     = 443
  description = "HTTPS Port number"
}

variable "enable_ssl" {
  type        = bool
  default     = true
  description = "Set to true to enable SSL support, requires variable ssl_certificates - a list of self_link certs"
}

variable "https_redirect" {
  description = "Set to `true` to enable https redirect on the lb"
  default     = false
  type        = bool
}

variable "buckets" {
  description = "Backend Buckets for GCS"
  type = map(object({
    name         = string
    location     = string
    service_name = string
    hosts        = list(string)
    path_rules = map(object({
      paths = list(string)
      url_redirect = list(object({
        host_redirect          = optional(string)
        path_redirect          = optional(string)
        https_redirect         = optional(bool, false)
        redirect_response_code = optional(number, 301)
        string_query           = optional(string)
      }))
    }))
    backend = optional(object({
      enable_cdn = optional(bool, false)
      cdn_policy = optional(object({
        cache_mode                   = optional(string)
        signed_url_cache_max_age_sec = optional(string)
        default_ttl                  = optional(number)
        max_ttl                      = optional(number)
        client_ttl                   = optional(number)
        negative_caching             = optional(bool)
        negative_caching_policy = optional(object({
          code = optional(number)
          ttl  = optional(number)
        }))
      }))
      cors_policy = optional(set(any))
      iap_config = optional(object({
        enable               = bool
        oauth2_client_id     = optional(string)
        oauth2_client_secret = optional(string)
      }))
      log_config = optional(object({
        enable      = optional(bool)
        sample_rate = optional(number)
      }))
    }))
  }))
}

variable "services" {
  description = "Cloud Run Services"
  type = map(object({
    hosts = list(string)
    path_rules = map(object({
      paths = list(string)
      url_redirect = list(object({
        host_redirect          = optional(string)
        path_redirect          = optional(string)
        https_redirect         = optional(bool, false)
        redirect_response_code = optional(number, 301)
        string_query           = optional(string)
      }))
    }))
    cloud_run_regions = list(object({
      region = string
      name   = string
    }))
    backend = optional(object({
      enable_cdn = optional(bool, false)
      iap_config = optional(object({
        enable               = bool
        oauth2_client_id     = optional(string)
        oauth2_client_secret = optional(string)
      }))
      log_config = optional(object({
        enable      = optional(bool)
        sample_rate = optional(number)
      }))
    }))
  }))
}
