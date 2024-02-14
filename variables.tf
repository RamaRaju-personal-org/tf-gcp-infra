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

variable "auto_create_subnetworks" {
  description = "mode selected"
  
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
}

variable "source_ranges" {
  description = "source range"
  type        = string
}

variable "dest_range" {
  description = "destination range"
  type        = string

}
