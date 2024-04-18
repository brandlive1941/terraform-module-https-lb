/******************************************
	Load Balancer Details
 *****************************************/

output "load_balancer_ip_address" {
  description = "IP address of the Cloud Load Balancer"
  value       = var.static_ip_name
}
