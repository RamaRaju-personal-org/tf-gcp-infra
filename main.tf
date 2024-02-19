
provider "google" {
  # Configuration options

  project = var.project
  region  = var.region
  zone    = var.zone
}


resource "google_compute_network" "custom_vpc" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "subnet1" {
  name          = var.subnet1_name
  ip_cidr_range = var.webapp_ip_cidr_rang
  region        = var.region
  network       = google_compute_network.custom_vpc.id

}

resource "google_compute_subnetwork" "subnet2" {
  name          = var.subnet2_name
  ip_cidr_range = var.db_ip_cidr_range
  region        = var.region
  network       = google_compute_network.custom_vpc.id
}

resource "google_compute_firewall" "allow-traffic-subnet1-webapp" {
  name    = "allow-traffic-subet1-webapp"
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.ports]
  }

  source_ranges = [var.source_ranges]
  target_tags   = ["subnet1"]
}

resource "google_compute_firewall" "allow-internal-subnet2-db" {
  name    = "allow-internal-subnet2-db"
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.db_ports]
  }

  source_tags   = ["subnet1"] # Allow traffic from only webapp instances
  target_tags   = ["subnet2"] # allow traffic to db instances
}

resource "google_compute_route" "custom-routes" {
  name             = "custom-routes"
  dest_range       = var.dest_range
  network          = google_compute_network.custom_vpc.id
  next_hop_gateway = "default-internet-gateway"
}



output "display_VPC" {
  value = google_compute_network.custom_vpc
}
