provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPC and Subnet
resource "google_compute_network" "vpc" {
  name                    = "k8s-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = "k8s-private-subnet"
  ip_cidr_range            = "10.10.0.0/16"
  region                   = var.region
  network                  = google_compute_network.vpc.name
  private_ip_google_access = true
}

# NAT for private VMs
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  network = google_compute_network.vpc.name
  region  = var.region
}

resource "google_compute_router_nat" "nat_config" {
  name                               = "nat-config"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_lb_traffic" {
  name    = "allow-lb-to-vm"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports = [
      "22",         # SSH
      "6443",       # Kubernetes API Server
      "8080",       # App port
      "9000",       # App port
      "9099",       # Health check
      "10250",      # Kubelet API
      "179",        # BGP for Calico
      "30000-32767" # NodePort Services
    ]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k8s-node"]
}

resource "google_compute_firewall" "allow_all_egress" {
  name    = "allow-all-egress"
  network = google_compute_network.vpc.name

  direction = "EGRESS"
  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
  priority           = 65534
}


# Create 1 Master and 2 Workers
resource "google_compute_instance" "master" {
  name         = "k8s-master"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["k8s-node"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = 50
    }
  }

  can_ip_forward = true

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    access_config {} # Private only
  }

  metadata_startup_script = var.startup_script
}

resource "google_compute_instance" "worker" {
  count        = 2
  name         = "k8s-worker-${count.index + 1}"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["k8s-node"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = 150
    }
  }

  can_ip_forward = true

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    access_config {} # Private only
  }

  metadata_startup_script = var.startup_script
}

# Create unmanaged instance group
resource "google_compute_instance_group" "k8s_group" {
  name = "k8s-group"
  zone = var.zone
  instances = [
    google_compute_instance.master.self_link,
    google_compute_instance.worker[0].self_link,
    google_compute_instance.worker[1].self_link
  ]

  named_port {
    name = "http"
    port = 8080
  }
}

# Health check 
resource "google_compute_health_check" "hc" {
  name = "http-health-check-ping"
  http_health_check {
    port         = 9000
    request_path = "/ping"
  }
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
}

# Backend service 
resource "google_compute_backend_service" "backend" {
  name          = "k8s-backend"
  protocol      = "HTTP"
  port_name     = "http"
  health_checks = [google_compute_health_check.hc.self_link]

  backend {
    group = google_compute_instance_group.k8s_group.self_link
  }
}

# URL map
resource "google_compute_url_map" "url_map" {
  name            = "k8s-url-map"
  default_service = google_compute_backend_service.backend.self_link
}

# HTTP proxy
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "k8s-http-proxy"
  url_map = google_compute_url_map.url_map.self_link
}

# Global static IP
resource "google_compute_global_address" "lb_ip" {
  name = "k8s-http-ip"
}

# Forwarding rule to expose on port 80
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name        = "k8s-http-forwarding"
  ip_address  = google_compute_global_address.lb_ip.address
  port_range  = "80"
  target      = google_compute_target_http_proxy.http_proxy.self_link
  ip_protocol = "TCP"
}
