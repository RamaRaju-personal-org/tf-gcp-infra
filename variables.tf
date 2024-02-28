variable "project" {
  description = "project name"
  type        = string

}

variable "region" {
  description = "selected region"
  type        = string

}

variable "zone" {
  description = "selected zone"
  type        = string

}

variable "vpc_name" {
  description = "name assigned"
  type        = string

}



variable "routing_mode" {
  description = "selected routing mode"
  type        = string

}

variable "webapp_ip_cidr_range" {
  description = "webapp cidr"
  type        = string
}


variable "db_ip_cidr_range" {
  description = "db cidr"
  type        = string
}

# variable "db_private_ip" {
#   description = "db private ip"
#   type        = string
# }

variable "protocol" {
  description = "protocol"
  type        = string
}


variable "ports" {
  description = "ports"
  type        = string

}

variable "db_ports" {
  description = "db ports"
  type        = string
}

variable "source_ranges" {
  description = "source range"
  type        = string

}

variable "dest_range" {
  description = "destination range"
  type        = string
}

variable "subnet1_name" {
  description = "subnet 1 name"
  type        = string
}

variable "subnet2_name" {
  description = "subnet 2 name"
  type        = string
}

variable "firewall1_name" {
  description = "firewall1_name"
  type        = string
}

variable "firewall2_name" {
  description = "firewall2_name"
  type        = string
}

variable "route_name" {
  description = "route_name"
  type        = string
}

variable "instance_name" {
  description = "instance_name"
  type        = string
}

variable "machine_type" {
  description = "machine_type"
  type        = string
}

variable "packer_image" {
  description = "packer_image"
  type        = string
}

variable "disk_type" {
  description = "disk_type"
  type        = string
}

variable "disk_size" {
  description = "disk_size"
  type        = string
}

variable "ssh_name" {
  description = "ssh_name"
  type        = string
}

variable "no_access_port" {
  description = "no_access_port"
  type        = string
}



variable "access_application_port_name" {
  description = "access_application_port_name"
  type        = string
}

variable "sql_db_name" {
  description = "sql_db_name"
  type        = string
}

variable "sql_db_user" {
  description = "sql_db_user"
  type        = string
}
