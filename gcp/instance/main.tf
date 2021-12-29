provider "google" {}

variable "project_id" {
  type = string
}

data "google_project" "wireguard" {
  project_id = var.project_id
}

variable "subnetwork" {
  type = string
}

data "google_compute_subnetwork" "wireguard" {
  self_link = var.subnetwork
}

variable "zone" {
  type = string
  default = ""
}

data "google_compute_zones" "zones" {
  project = var.project_id
  region = data.google_compute_subnetwork.wireguard.region
  status = "UP"
}

resource "random_shuffle" "zone" {
  input = data.google_compute_zones.zones.names
}

locals {
  zone = var.zone != "" ? var.zone : random_shuffle.zone.result[0]
}

variable "cidr" {
  type = string
  default = "192.168.78.0/24"
}

variable "source_ranges" {
  type = list(string)
  description = "Range of IPs allowed through the GCP firewall"
}

locals {
  cidr_prefix = split("/", var.cidr)[1]
  gateway = "${cidrhost(var.cidr, 1)}/${local.cidr_prefix}"
}

variable "peers" {
  type = list(string)
}

variable "listen_port" {
  type = number
  default = 51820
}

resource "google_compute_firewall" "wireguard" {
  project = data.google_project.wireguard.project_id
  name = "wireguard"
  network = data.google_compute_subnetwork.wireguard.network

  direction = "INGRESS"
  allow {
    protocol = "udp"
    ports    = [var.listen_port]
  }
  source_ranges = var.source_ranges
  target_tags = ["wg"]
}

resource "google_secret_manager_secret" "wireguard-pubkey" {
  secret_id = "wireguard-pubkey"
  labels = {}
  project = data.google_project.wireguard.project_id
  replication {
    automatic = "true"
  }
}
locals {
  runcmds = "- [gcloud, secrets, versions, add, ${google_secret_manager_secret.wireguard-pubkey.secret_id}, --data-file=/etc/wireguard/pubkey]"
  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    peers = var.peers,
    listen_port = var.listen_port,
    runcmds = local.runcmds,
    cidr = var.cidr,
    gateway = local.gateway,
  })
}

resource "google_compute_instance" "wireguard" {
  project = data.google_project.wireguard.project_id
  name = "wireguard"
  zone = local.zone

  tags = ["wg"]
  machine_type = "e2-micro"

  labels = {}
  resource_policies = []

  network_interface {
    subnetwork = data.google_compute_subnetwork.wireguard.self_link
    access_config {
      network_tier = "STANDARD"
    }
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-2004-lts"
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

  provisioner "local-exec" {
    command = <<EOF
      bash -c "while gcloud --project ${self.project} secrets versions list wireguard-pubkey --limit 1 --format json | jq --exit-status 'length == 0 or (.[0].state == \"DISABLED\")'>/dev/null; do
        echo 'Waiting for pubkey secret...' && sleep 10
      done"
    EOF
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
      bash -c "gcloud --project ${self.project} secrets versions disable --secret wireguard-pubkey \
         $(gcloud --project ${self.project} secrets versions list --format json wireguard-pubkey --limit 1 | jq -r '.[0].name')
      "
    EOF
  }
}

data "google_secret_manager_secret_version" "pubkey" {
  depends_on = [
    google_compute_instance.wireguard,
  ]
  project = data.google_project.wireguard.project_id
  secret = google_secret_manager_secret.wireguard-pubkey.secret_id
}

locals {
  endpoint_ip = google_compute_instance.wireguard.network_interface[0].access_config[0].nat_ip
  public_key = data.google_secret_manager_secret_version.pubkey.secret_data
  interface_extra = <<EOF
MTU = 1380
  EOF
}

output "ip" {
  value = trimspace(local.endpoint_ip)
}
output "public_key" {
  sensitive = true
  value = trimspace(local.public_key)
}
output "interface_extra" {
  value = trimspace(local.interface_extra)
}
output "port" {
  value = var.listen_port
}
