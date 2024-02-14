
provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}


resource "google_compute_network" "asssignment-3" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = var.webapp_ip_cidr_range
  region        = var.region
  network       = google_compute_network.asssignment-3.id

}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = var.db_ip_cidr_range
  region        = var.region
  network       = google_compute_network.asssignment-3.id
}

resource "google_compute_firewall" "allow-traffic-webapp" {
  name    = "allow-traffic-webapp"
  network = google_compute_network.asssignment-3.id

  allow {
    protocol = var.protocol
    ports    = [var.ports]
  }

  source_ranges = [var.source_ranges]
  target_tags   = ["webapp"]
}

resource "google_compute_firewall" "allow-internal-db" {
  name    = "allow-internal-db"
  network = google_compute_network.asssignment-3.id

  allow {
    protocol = var.protocol
    ports    = [var.db_ports]
  }

  source_tags   = ["webapp"] # Allow traffic from only webapp instances
  target_tags   = ["db"] # allow traffic to db instances
}

resource "google_compute_route" "a3-routes" {
  name             = "a3-routes"
  dest_range       = var.dest_range
  network          = google_compute_network.asssignment-3.id
  next_hop_gateway = "default-internet-gateway"
}



output "display_VPC" {
  value = google_compute_network.asssignment-3
}
