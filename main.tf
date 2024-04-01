provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}
data "google_project" "project" {
  project_id = var.project
}
# provider "google-beta" {
#   project = var.project
#   region  = var.region
# }
// for sending the application.zip to gcp storage bucket
# provider "local" {
#   version = "~> 2.0"
# }

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
  private_ip_google_access = true  // Enable Private Google Access
}

resource "google_compute_subnetwork" "subnet2" {
  name                     = var.subnet2_name
  ip_cidr_range            = var.db_ip_cidr_range
  region                   = var.region
  network                  = google_compute_network.custom_vpc.id
  private_ip_google_access = true
}

// allow traffic on desired port to the subnet
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


// allow traffic on port 80 to the webapp instance where the application is running
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
# resource "google_compute_instance" "my_instance" {
#   name         = var.instance_name
#   machine_type = var.machine_type
#   zone         = var.zone

#   // Allow the instance to be stopped if machine type or other specified properties need to be updated
#   allow_stopping_for_update = true

#   boot_disk {
#     initialize_params {
#       image = var.packer_image
#       type  = var.disk_type
#       size  = var.disk_size
#     }
#   }

#   network_interface {
#     network    = google_compute_network.custom_vpc.id
#     subnetwork = google_compute_subnetwork.subnet1.id

#     //public ip allocation
#     access_config {

#     }
#   }


#   tags = ["webapp-instance-tag", "ssh-access"]


#   depends_on = [
#     google_sql_database_instance.my_sql_instance,
#     google_sql_user.webapp_user,
#     google_service_networking_connection.private_vpc_connection,
#     google_compute_firewall.allow-access-to-application-port
#   ]


#   metadata_startup_script = <<-EOF
#       #!/bin/bash
#       mkdir -p /opt/csye6225
#       chown csye6225:csye6225 /opt/csye6225
#       cat <<-EOL > /opt/csye6225/.env
#       DB_NAME=${google_sql_database.webapp_db.name}
#       DB_USER=${google_sql_user.webapp_user.name}
#       DB_PASSWORD=${random_password.password.result}
#       DB_HOST=${google_sql_database_instance.my_sql_instance.private_ip_address}
#       PORT=3307
#       MAILGUN_API_KEY=${var.mailgun_api_key}
#       MAILGUN_DOMAIN=${var.mailgun_domain}
#       EOL
#       cd
#       sudo systemctl daemon-reload
#       sudo systemctl enable nodeapp
#       sudo systemctl restart nodeapp
#     EOF

#   # service_account {
#   #   email  = google_service_account.vm_service_account.email
#   #   scopes = ["https://www.googleapis.com/auth/cloud-platform"]
#   # }

#   service_account {
#     email  = "teraform-gcp@csye6225-413808.iam.gserviceaccount.com"
#     scopes = ["https://www.googleapis.com/auth/cloud-platform"]
#   }
# }




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
  source_ranges = ["0.0.0.0/0"] // CAUTION: This allows access from any IP. For production, restrict to specific IPs.

  target_tags = ["ssh-access"] // Apply this rule to instances tagged with "ssh-access"
}






# get the managed dns zone 
data "google_dns_managed_zone" "dns_zone" {
  name = "ram-public-zone"
}

#add the ip address to the dns i.e adding A record 
resource "google_dns_record_set" "website" {
  name         = "ramaraju.me."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  # rrdatas      = [google_compute_instance.my_instance.network_interface.0.access_config.0.nat_ip]
  rrdatas = [google_compute_global_address.default.address]
}

# resource "google_service_account" "vm_service_account" {
#   account_id   = "my-vm-service-account"
#   display_name = "Service Account for VM Instances"
# }

// pubsub.publisher role for vm service account so that 
// application running on the vm can publish the user creation message to pub/sub topic 
resource "google_project_iam_member" "vm_service_account_pubsub_publisher" {
  project = var.project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"

}


resource "google_project_iam_binding" "logging_admin" {
  project = var.project
  role    = "roles/logging.admin"
  members = [
    "serviceAccount:${google_service_account.cdn_service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.cdn_service_account.email}",
  ]
}

# mail records 
resource "google_dns_record_set" "spf_record" {
  name         = var.spf_name
  type         = "TXT"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = var.spf_rrdata
}

resource "google_dns_record_set" "dkim_record" {
  name         = var.dkim_name
  type         = "TXT"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = var.dkim_rrdata
}

resource "google_dns_record_set" "mx_record" {
  name         = var.mx_name
  type         = "MX"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [for mx in var.mx_rrdatas : "${mx}"]
}


resource "google_dns_record_set" "cname_record" {
  name         = var.cname_name
  type         = "CNAME"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = var.cname_rrdata
}







# service account for cloud function 
resource "google_service_account" "cdn_service_account" {
  account_id   = "my-cdn-service-account"
  display_name = "Service Account for CDN"
}


//pub sub topic 
resource "google_pubsub_topic" "verify_email_topic" {
  name = "verify_email"
}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = "verify_email_subscription"
  topic = google_pubsub_topic.verify_email_topic.id

  message_retention_duration = "604800s" // 7 days in seconds
  ack_deadline_seconds       = 20

}


resource "google_pubsub_topic_iam_binding" "pubsub_publisher_binding" {
  topic = google_pubsub_topic.verify_email_topic.id
  role  = "roles/pubsub.publisher"

  members = [
    "serviceAccount:${google_service_account.cdn_service_account.email}",
  ]
}

resource "google_storage_bucket" "bucket" {
  name                        = "${var.project}-gcf-source" # Every bucket name must be globally unique
  location                    = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "f.zip" # Add path to the zipped function source code
}



resource "google_project_service" "serverless_vpc_access_api" {
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_vpc_access_connector" "serverless_connector" {
  depends_on = [
    google_project_service.serverless_vpc_access_api,
    google_compute_network.custom_vpc
  ]

  name          = "serverless-vpc-connector"
  project       = var.project
  region        = var.region
  network       = google_compute_network.custom_vpc.id
  ip_cidr_range = "10.0.5.0/28" # Choose a range that does not overlap with existing subnets.
}



resource "google_project_iam_member" "cloud_sql_client" {
  project = var.project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"

}


# // Adjust the following Cloud Function resource to use the newly created bucket
resource "google_cloudfunctions2_function" "email_verification" {
  name        = "emailVerificationFunction"
  location    = var.region
  description = "Function to send verification email upon user creation"

  build_config {
    entry_point = "handleNewUser"
    runtime     = "nodejs20" // Ensure you use the correct runtime for your function

    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }

    environment_variables = {
      // Define your environment variables here
      DB_NAME                  = google_sql_database.webapp_db.name
      DB_USER                  = google_sql_user.webapp_user.name
      DB_PASSWORD              = random_password.password.result
      DB_HOST                  = google_sql_database_instance.my_sql_instance.private_ip_address
      MAILGUN_API_KEY          = var.mailgun_api_key
      MAILGUN_DOMAIN           = var.mailgun_domain
      INSTANCE_CONNECTION_NAME = "${var.project}:${var.region}:${google_sql_database_instance.my_sql_instance.name}"

      // Any other env vars your function needs
    }

  }



  service_config {
    available_memory               = "256M" // Match this to the expected memory need of your function
    timeout_seconds                = 120
    min_instance_count             = 0
    max_instance_count             = 1                     // Adjust max instances as needed for your use case
    ingress_settings               = "ALLOW_INTERNAL_ONLY" // Change to ""ALLOW_ALL"" or "ALLOW_INTERNAL_AND_GCLB" as per your needs
    all_traffic_on_latest_revision = true
    // Uncomment the next line if you have a dedicated service account
    service_account_email = google_service_account.cdn_service_account.email
    # service_account_email = "teraform-gcp@csye6225-413808.iam.gserviceaccount.com"

    vpc_connector = google_vpc_access_connector.serverless_connector.id


  }

  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.verify_email_topic.id
    retry_policy = "RETRY_POLICY_RETRY"

  }
}

resource "google_project_iam_member" "cloud_run_invoker" {
  project = var.project
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"
}


// IAM role for Cloud Storage view access

resource "google_storage_bucket_iam_member" "cloud_function_bucket_object_viewer" {
  bucket = google_storage_bucket.bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cdn_service_account.email}"
  # member = "serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"
}


//cf subscriber to the pub/sub topic
resource "google_pubsub_subscription_iam_binding" "cloud_function_subscriber" {
  subscription = google_pubsub_subscription.verify_email_subscription.name
  role         = "roles/pubsub.subscriber"

  members = [
    "serviceAccount:${google_service_account.cdn_service_account.email}",
  ]
  # members = ["serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"]

}

resource "google_pubsub_topic_iam_member" "subscriber_member" {
  topic  = google_pubsub_topic.verify_email_topic.id
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.cdn_service_account.email}"
  # member = "serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"

}

// IAM Binding for the Cloud Functions Service Account:
resource "google_project_iam_member" "cloudfunctions_developer" {
  project = var.project
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"
  # member = "serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"

}




// IAM Binding for the Service Agent Role
resource "google_project_iam_member" "service_agent" {
  project = var.project
  role    = "roles/cloudfunctions.serviceAgent"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcf-admin-robot.iam.gserviceaccount.com"
}




output "cloud_function_name" {
  value = google_cloudfunctions2_function.email_verification.name
}

output "cloud_function_pubsub_topic" {
  value = google_pubsub_topic.verify_email_topic.name
}




# # IAM policy for Cloud Functions CloudFunction
# data "google_iam_policy" "cf" {
#   binding {
#     role = "roles/viewer"

#     members = [
#       "serviceAccount:${google_service_account.cdn_service_account.email}",
#     ]
#   }
# }

# resource "google_cloudfunctions_function_iam_policy" "function_iam_policy" {
#   project        = var.project
#   region         = var.region
#   cloud_function = google_cloudfunctions2_function.email_verification.name

#   policy_data = data.google_iam_policy.cf.policy_data
#   depends_on = [google_cloudfunctions2_function.email_verification]
# }



# # IAM policy for Pub/Sub Subscription

data "google_iam_policy" "subscriber" {
  binding {
    role = "roles/editor"

    members = [
      "serviceAccount:${google_service_account.cdn_service_account.email}",
    ]
    # members = ["serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"]

  }
}
resource "google_pubsub_subscription_iam_policy" "subscription_iam_policy" {
  subscription = google_pubsub_subscription.verify_email_subscription.name
  project      = var.project

  policy_data = data.google_iam_policy.subscriber.policy_data
}



////////

# # IAM policy for Cloud Pub/Sub Topic

data "google_iam_policy" "admin" {
  binding {
    role = "roles/viewer"

    members = [
      "serviceAccount:${google_service_account.cdn_service_account.email}",
    ]
    # members = ["serviceAccount:teraform-gcp@csye6225-413808.iam.gserviceaccount.com"]

  }
}
resource "google_pubsub_topic_iam_policy" "topic_iam_policy" {
  topic   = google_pubsub_topic.verify_email_topic.name
  project = var.project

  policy_data = data.google_iam_policy.admin.policy_data
}




# Outputs
# output "instance_name" {
#   value = google_compute_instance.my_instance.name
# }

output "sql_instance_private_ip" {
  value = google_sql_database_instance.my_sql_instance.private_ip_address
}

output "serverless_connector_name" {
  value = google_vpc_access_connector.serverless_connector.name
}

output "serverless_connector_id" {
  value = google_vpc_access_connector.serverless_connector.id
}





# Provider configuration is assumed to be declared outside this snippet



resource "google_project_iam_member" "pubsub_publisher_iam" {
  project = var.project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"
}

# Regional Compute Instance Template
resource "google_compute_instance_template" "webapp_template" {
  name_prefix  = "webapp-template-"
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = var.packer_image
  }

  network_interface {
    network    = google_compute_network.custom_vpc.self_link
    subnetwork = google_compute_subnetwork.subnet1.self_link
  }

  lifecycle {
    create_before_destroy = true
  }
  tags = ["webapp-lb-target", "ssh-access", "webapp-instance-tag"] # This tag is used in the firewall rule

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      mkdir -p /opt/csye6225
      chown csye6225:csye6225 /opt/csye6225
      cat <<-EOL > /opt/csye6225/.env
      DB_NAME=${google_sql_database.webapp_db.name}
      DB_USER=${google_sql_user.webapp_user.name}
      DB_PASSWORD=${random_password.password.result}
      DB_HOST=${google_sql_database_instance.my_sql_instance.private_ip_address}
      PORT=3307
      MAILGUN_API_KEY=${var.mailgun_api_key}
      MAILGUN_DOMAIN=${var.mailgun_domain}
      EOL
      cd
      sudo systemctl daemon-reload
      sudo systemctl enable nodeapp
      sudo systemctl restart nodeapp
    EOT

  }
  service_account {
    email  = google_service_account.cdn_service_account.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

# Compute Health Check
resource "google_compute_health_check" "webapp_health_check" {
  name               = "webapp-health-check"
  check_interval_sec = 5
  timeout_sec        = 5
  http_health_check {
    request_path = "/healthz"
    port         = 3307
  }
}

# Compute Autoscaler
resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.webapp_manager.id

  autoscaling_policy {
    max_replicas    = 3
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.05
    }
  }
}

# Regional Instance Group Manager
resource "google_compute_region_instance_group_manager" "webapp_manager" {
  name               = "webapp-manager"
  region             = var.region
  base_instance_name = "webapp"

  version {
    name              = "v1"
    instance_template = google_compute_instance_template.webapp_template.self_link
  }

  target_size = 1
  lifecycle {
    ignore_changes = [target_size]
  }

  named_port {
    name = "http"
    //This name given to the 'named_port' in the MIG must match the 'port_name' in the 'google_compute_backend_service'
    port = "3307"
  }
  update_policy {

    type = "PROACTIVE"
    //MIG 'proactively' executes actions in order to bring instances to their target template version

    instance_redistribution_type = "PROACTIVE"
    //MIG attempts to maintain an even distribution of VM instances across all the zones in the region

    minimal_action = "REPLACE"
    //'REFRESH' updates without stopping existing instances,
    //'RESTART' updates by restarting existing instances,
    //'REPLACE' updates by deleting and recreating existing instances

    most_disruptive_allowed_action = "REPLACE"
    //Specifies the most disruptive action that is allowed to be taken on an instance
    //'REPLACE' is the most aggressive action

    max_surge_fixed = 3
    // Allows for one additional instance during updates

    # replacement_method = "RECREATE"
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.webapp_health_check.self_link
    initial_delay_sec = 300
  }
}


# Firewall rules to allow only load balancer
resource "google_compute_firewall" "webapp_allow_lb" {
  name    = "webapp-allow-lb"
  network = google_compute_network.custom_vpc.self_link # Reference to your network resource

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Google Cloud Load Balancers (HTTP/S, SSL proxy, and TCP proxy) use these IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["webapp-lb-target", "webapp-instance-tag"] # This tag should be assigned to instances that the LB will route to
}


# Create a global IP for Load Balancer
resource "google_compute_global_address" "default" {
  name = "webapp-global-address"
}

# Backend service for Load Balancer
resource "google_compute_backend_service" "default" {
  name          = "webapp-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.webapp_health_check.self_link]
  backend {
    group = google_compute_region_instance_group_manager.webapp_manager.instance_group
  }
}

# URL Map for Load Balancer
resource "google_compute_url_map" "default" {
  name            = "webapp-url-map"
  default_service = google_compute_backend_service.default.self_link

}

# HTTP(S) Proxy for Load Balancer
resource "google_compute_target_https_proxy" "default" {
  name             = "webapp-http-proxy"
  url_map          = google_compute_url_map.default.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.default.self_link]
}

# SSL Certificates
resource "google_compute_managed_ssl_certificate" "default" {
  name = "webapp-ssl-cert"
  managed {
    domains = ["ramaraju.me"]
  }
}

# Forwarding Rule for Load Balancer
resource "google_compute_global_forwarding_rule" "https" {
  name       = "webapp-forwarding-rule"
  target     = google_compute_target_https_proxy.default.self_link
  port_range = "443"
  ip_address = google_compute_global_address.default.address
}

# Assign DNS Administrator role to the cdn_service_account
resource "google_project_iam_member" "cdn_service_account_dns_admin" {
  project = var.project
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"
}

# Assign Compute Load Balancer Admin role to the cdn_service_account
resource "google_project_iam_member" "cdn_service_account_lb_admin" {
  project = var.project
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.cdn_service_account.email}"
}
# DNS Record Update
# resource "google_dns_record_set" "frontend" {
#   name         = "your-domain.com."
#   type         = "A"
#   ttl          = 300
#   managed_zone = "your-managed-zone"
#   rrdatas      = [google_compute_global_address.default.address]
# }
