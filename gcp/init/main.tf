provider "google" {}

resource "random_string" "id_suffix" {
  length = 6
  lower = false
  upper = false
  special = false
}

variable "billing_account" {
  type = string
}

data "google_billing_account" "account" {
  billing_account = var.billing_account
  open            = true
}

resource "google_project" "wireguard" {
  name = "Wireguard"
  project_id = "wireguard-${random_string.id_suffix.result}"

  billing_account = data.google_billing_account.account.id
}

variable "region" {
  type = string
  default = ""
}

locals {
  region = var.region != "" ? var.region : null
}

resource "google_project_service" "compute" {
  project = google_project.wireguard.project_id
  service = "compute.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project = google_project.wireguard.project_id
  service = "secretmanager.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy = false
}

resource "google_compute_network" "wireguard" {
  name = "wireguard"
  project = google_project_service.compute.project
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "wireguard" {
  name = "wireguard"
  ip_cidr_range = "10.0.0.0/24"
  project = google_project_service.compute.project
  network = google_compute_network.wireguard.name
  private_ip_google_access = true
  region = local.region
}

output "project_id" {
  value = google_project.wireguard.project_id
}
output "subnetwork" {
  value = google_compute_subnetwork.wireguard.self_link
}
