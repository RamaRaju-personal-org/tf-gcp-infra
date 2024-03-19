provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

provider "random" {
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "random_string" "instance_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "google_compute_network" "custom_vpc" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_route" "custom-routes" {
  name             = var.route_name
  dest_range       = var.dest_range
  network          = google_compute_network.custom_vpc.id
  next_hop_gateway = "default-internet-gateway"
}



resource "google_compute_subnetwork" "subnet1" {
  name          = var.subnet1_name
  ip_cidr_range = var.webapp_ip_cidr_range
  region        = var.region
  network       = google_compute_network.custom_vpc.id
}

resource "google_compute_subnetwork" "subnet2" {
  name                     = var.subnet2_name
  ip_cidr_range            = var.db_ip_cidr_range
  region                   = var.region
  network                  = google_compute_network.custom_vpc.id
  private_ip_google_access = true
}

// allow traffic on port 3307 to the subnet
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


// allow traffic on port 3307 to the webapp instance where the application is running
resource "google_compute_firewall" "allow-access-to-application-port" {
  name    = var.access_application_port_name
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.ports]
  }

  source_ranges = [var.source_ranges]
  target_tags   = ["webapp-instance-tag"] # Apply this rule to instances in subnet1
}

resource "google_compute_firewall" "allow-db-access" {
  name    = var.firewall2_name
  network = google_compute_network.custom_vpc.id

  allow {
    protocol = var.protocol
    ports    = [var.db_ports]
  }

  source_tags = ["webapp-instance-tag"]
  target_tags = [var.subnet2_name]
}



resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.vpc_name}-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24 //cidr range
  network       = google_compute_network.custom_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.custom_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "my_sql_instance" {
  name             = "sql-instance-${random_string.instance_suffix.result}"
  database_version = "MYSQL_5_7"
  region           = var.region

  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL" // enabling "REGIONAL" will ask you to enable binary logging for High availabilty.
    // if you don't need HA go with ZONAL
    disk_size = var.disk_size
    disk_type = "PD_SSD"
    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.custom_vpc.self_link
      # Correct reference to the VPC network
      # authorized_networks {
      #   name  = "subnet1"
      #   value = google_compute_subnetwork.subnet1.ip_cidr_range
      # }
    }
  }

  deletion_protection = false
  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]

}

resource "google_sql_database" "webapp_db" {
  name     = var.sql_db_name
  instance = google_sql_database_instance.my_sql_instance.name
}

resource "google_sql_user" "webapp_user" {
  name     = var.sql_db_user
  instance = google_sql_database_instance.my_sql_instance.name
  password = random_password.password.result
}



# Compute Engine Instance with Startup Script
resource "google_compute_instance" "my_instance" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.packer_image
      type  = var.disk_type
      size  = var.disk_size
    }
  }

  network_interface {
    network    = google_compute_network.custom_vpc.id
    subnetwork = google_compute_subnetwork.subnet1.id

    //public ip allocation
    access_config {

    }
  }


  tags = ["webapp-instance-tag", "ssh-access"]


  depends_on = [
    google_sql_database_instance.my_sql_instance,
    google_sql_user.webapp_user,
    google_service_networking_connection.private_vpc_connection,
    google_compute_firewall.allow-access-to-application-port
  ]


  metadata_startup_script = <<-EOF
      #!/bin/bash
      mkdir -p /opt/csye6225
      chown csye6225:csye6225 /opt/csye6225
      cat <<-EOL > /opt/csye6225/.env
      DB_NAME=${google_sql_database.webapp_db.name}
      DB_USER=${google_sql_user.webapp_user.name}
      DB_PASSWORD=${random_password.password.result}
      DB_HOST=${google_sql_database_instance.my_sql_instance.private_ip_address}
      PORT=3307
      EOL
      cd
      sudo systemctl daemon-reload
      sudo systemctl enable nodeapp
      sudo systemctl restart nodeapp
    EOF

    service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}




# resource "google_compute_firewall" "ssh-deny-for-all-ip" {
#   name    = var.ssh_name
#   network = google_compute_network.custom_vpc.id

#   deny {
#     protocol = var.protocol
#     ports    = [var.no_access_port]
#   }

#   source_ranges = [var.source_ranges]
#   target_tags   = ["webapp-instance-tag"] # Apply this rule to instances in subnet1
# }

//ssh allow for google compute & commented, also add the tag to compute instance when using allow_ssh
resource "google_compute_firewall" "allow_ssh" {
  name    = "ssh-allow"
  network = google_compute_network.custom_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  // Use source ranges to define IP ranges that are allowed to access
  source_ranges = ["0.0.0.0/0"]  // CAUTION: This allows access from any IP. For production, restrict to specific IPs.

  target_tags = ["ssh-access"]  // Apply this rule to instances tagged with "ssh-access"
}


# get the managed dns zone 
data "google_dns_managed_zone" "dns_zone"{
  name = "ram-public-zone"
}

#add the ip address to the dns i.e adding A record 
resource "google_dns_record_set" "website" {
  name         = "ramaraju.me."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [google_compute_instance.my_instance.network_interface.0.access_config.0.nat_ip]
}

resource "google_service_account" "vm_service_account" {
  account_id   = "my-vm-service-account"
  display_name = "Service Account for VM Instances"
}


resource "google_project_iam_binding" "logging_admin" {
  project = var.project
  role    = "roles/logging.admin"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}
# Outputs
output "instance_name" {
  value = google_compute_instance.my_instance.name
}

output "sql_instance_private_ip" {
  value = google_sql_database_instance.my_sql_instance.private_ip_address
}
