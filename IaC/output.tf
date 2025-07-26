output "load_balancer_ip" {
  description = "Public IP of the TCP Load Balancer"
  value       = google_compute_global_address.lb_ip.address
}
