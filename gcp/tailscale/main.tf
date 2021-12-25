terraform {
  required_providers {
    tailscale = {
      source = "davidsbond/tailscale"
    }
  }
}

provider "google" {}

variable "tailnet" {
  type = string
}

variable "tailscale_api_key" {
  type = string
}

provider "tailscale" {
  tailnet = var.tailnet
  api_key = var.tailscale_api_key
}

variable "tags" {
  type = set(string)
}

resource "tailscale_tailnet_key" "gcp" {
  // non-reusable broken at the moment
  reusable = true
  tags     = var.tags
}

variable "subnetwork" {
  type = string
}

data "google_compute_subnetwork" "wireguard" {
  self_link = var.subnetwork
}

variable "zone" {
  type    = string
  default = ""
}

data "google_compute_zones" "zones" {
  project = data.google_compute_subnetwork.wireguard.project
  region  = data.google_compute_subnetwork.wireguard.region
  status  = "UP"
}

resource "random_shuffle" "zone" {
  input = data.google_compute_zones.zones.names
}

locals {
  zone = var.zone != "" ? var.zone : random_shuffle.zone.result[0]
}

locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    key = tailscale_tailnet_key.gcp.key,
  })
}

resource "google_compute_instance" "tailscale" {
  project = data.google_compute_subnetwork.wireguard.project
  name    = "gcp"
  zone    = local.zone

  tags         = ["tailscale"]
  machine_type = "e2-micro"

  network_interface {
    subnetwork = data.google_compute_subnetwork.wireguard.self_link
    access_config {
      network_tier = "STANDARD"
    }
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-minimal-2110-impish-v20211207"
    }
  }

  metadata = {
    user-data = local.cloud_init
  }
  metadata_startup_script = <<EOF
    exit 0
    #${sha256(local.cloud_init)}
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}
