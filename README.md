# terraform-module-https-lb
terraform module for creating an opinionated gcp load balancer

Module Input Variables
----------------------

- `project` - gcp project id
- `region` - gcp region
- `environment` - logical environment
- `static_ip_name` - global load balancer name
- `certificate_map` - certificate map to attach to load balancer
- `services` - map cloud run service metadata
- `buckets` - map of gcs bucket metadata

Usage
-----

```hcl
module "example-lb" {
  source          = "github.com/brandlive1941/terraform-module-backend-serverless?ref=v1.0.1"

  project_id      = var.project_id
  region          = var.region
  environment     = var.environment
  static_ip_name  = var.static_ip_name
  certificate_map = var.certificate_map
  services        = var.services
  buckets         = var.buckets
}
```

Outputs
=======

Authors
=======

drew.mercer@brandlive.com