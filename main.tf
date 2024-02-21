
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
  ip_cidr_range = var.webapp_ip_cidr_range
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
  name    = var.firewall1_name
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.ports]
  }

  source_ranges = [var.source_ranges]
  target_tags   = [var.subnet1_name]
}

resource "google_compute_firewall" "allow-internal-subnet2-db" {
  name    = var.firewall2_name
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.db_ports]
  }

  source_tags   = [var.subnet1_name] # Allow traffic from only webapp instances
  target_tags   = [var.subnet2_name] # allow traffic to db instances
}

resource "google_compute_route" "custom-routes" {
  name             = var.route_name
  dest_range       = var.dest_range
  network          = google_compute_network.custom_vpc.id
  next_hop_gateway = "default-internet-gateway"
}



# New resource for the compute instance
resource "google_compute_instance" "my_instance" {
  name         = var.instance_name
  machine_type = var.machine_type # Replace with your desired machine type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.packer_image # Replace with the actual name or URL of the custom image
      type  = var.disk_type
      size  = var.disk_size
    }
  }

  network_interface {
    network = google_compute_network.custom_vpc.name
    subnetwork = google_compute_subnetwork.subnet1.name

    access_config {

    }
  }
   tags = ["my-application-instance"]

}

resource "google_compute_firewall" "ssh-deny-for-all-ip" {
  name    = var.ssh_name
  network = google_compute_network.custom_vpc.id

  deny {
    protocol = var.protocol
    ports    = [var.no_access_port]
  }

  source_ranges = [var.source_ranges] 
  target_tags   = ["my-application-instance"]  # Apply this rule to instances in subnet1
}




resource "google_compute_firewall" "allow-access-to-application-port" {
  name    = var.access_application_port_name
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.ports]
  }

  source_ranges = [var.source_ranges] # Replace with your actual IP address
  target_tags   = ["my-application-instance"]  # Apply this rule to instances in subnet1
}

output "display_VPC" {
  value = google_compute_network.custom_vpc
}
