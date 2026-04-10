output "vpc_id" {
  description = "Self-link of the VPC"
  value       = google_compute_network.main.self_link
}

output "public_subnet_id" {
  description = "Self-link of the public subnet"
  value       = google_compute_subnetwork.public.self_link
}

output "private_subnet_id" {
  description = "Self-link of the private subnet"
  value       = google_compute_subnetwork.private.self_link
}

output "web_instance_name" {
  description = "Name of the web instance"
  value       = google_compute_instance.web.name
}

output "web_external_ip" {
  description = "External IP of the web instance"
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "app_instance_name" {
  description = "Name of the app instance"
  value       = google_compute_instance.app.name
}

output "app_internal_ip" {
  description = "Internal IP of the app instance"
  value       = google_compute_instance.app.network_interface[0].network_ip
}

output "bastion_external_ip" {
  description = "External IP of the bastion instance"
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

output "compute_service_account_email" {
  description = "Email of the compute service account"
  value       = google_service_account.compute.email
}
