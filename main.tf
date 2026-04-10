terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── VPC Network ─────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${var.env}-vpc"
  auto_create_subnetworks = false
  description             = "Main VPC for ${var.env} environment"
}

# ─── Subnets ─────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "public" {
  name          = "${var.env}-public-subnet"
  ip_cidr_range = var.public_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "private" {
  name          = "${var.env}-private-subnet"
  ip_cidr_range = var.private_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ─── Cloud Router + NAT (for private subnet egress) ──────────────────────────

resource "google_compute_router" "main" {
  name    = "${var.env}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.env}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ─── Firewall Rules ───────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.env}-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.public_subnet_cidr, var.private_subnet_cidr]

  target_tags = ["internal"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.env}-allow-ssh-iap"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP CIDR — allows SSH tunnelling via Cloud IAP without a public IP
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["ssh-iap"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.env}-allow-http-https"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.env}-deny-all-ingress"
  network  = google_compute_network.main.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ─── Compute Instances ────────────────────────────────────────────────────────

# Web server (public subnet, external IP)
resource "google_compute_instance" "web" {
  name         = "${var.env}-web-01"
  machine_type = var.web_machine_type
  zone         = "${var.region}-a"

  tags   = ["web", "ssh-iap", "internal"]
  labels = merge(var.common_labels, { role = "web", tier = "frontend" })

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
      labels = merge(var.common_labels, { role = "web" })
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOT

  service_account {
    email  = google_service_account.compute.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# App server (private subnet, no external IP)
resource "google_compute_instance" "app" {
  name         = "${var.env}-app-01"
  machine_type = var.app_machine_type
  zone         = "${var.region}-b"

  tags   = ["ssh-iap", "internal"]
  labels = merge(var.common_labels, { role = "app", tier = "backend" })

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-balanced"
      labels = merge(var.common_labels, { role = "app" })
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config block = no external IP
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.compute.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# Bastion host (public subnet, minimal footprint)
resource "google_compute_instance" "bastion" {
  name         = "${var.env}-bastion-01"
  machine_type = var.bastion_machine_type
  zone         = "${var.region}-a"

  tags   = ["ssh-iap", "internal"]
  labels = merge(var.common_labels, { role = "bastion", tier = "management" })

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
      labels = merge(var.common_labels, { role = "bastion" })
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    access_config {
      # Ephemeral public IP — intentional for bastion
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.compute.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# ─── Service Account ─────────────────────────────────────────────────────────

resource "google_service_account" "compute" {
  account_id   = "${var.env}-compute-sa"
  display_name = "Compute Service Account (${var.env})"
  description  = "Used by Compute Engine instances in ${var.env}"
}
