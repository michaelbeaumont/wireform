# Wireform

Wireform is a collection of `terraform` modules for _complete initialization_ of
a `wireguard` endpoint in the cloud for use as a VPN.

The goal of this project is to make it _very easy_ to build and tear down a
wireguard endpoint in the cloud, such that one can be created and destroyed
on demand.

## Prerequisites

Check the provider folders for requirements.

## Usage

This repo is a set of provider-specific modules for setting up a wireguard
endpoint, accessible only with the keys you provide when setting up
the instance. The private key also never leaves the VM!

Note: None of example keys here are in use. :wink:

### Provider-specific

For example, with GCP, the following terraform can be used to set up the
wireguard endpoint.

```
module "init" {
  source = "./init"

  billing_account = "01C913-9473DA-F05E90"
  region = "us-east1"
}

module "instance" {
  source = "./instance"

  project_id = module.init.project_id
  subnetwork = module.init.subnetwork
  source_ranges = [
    "2.2.2.2/32",
  ]
  peers = [
    <<EOF
      PublicKey = cralfZjaxUU61lhBFuQAY4s0H6oIdNyyOKo1jxuY/hg=
      AllowedIPs = 192.168.78.2/32"
    EOF
  ]
}
```

There are more variables in the `instance` module, check
[`gcp/instance`](gcp/instance/main.tf).

#### Outputs

- `instance.interface` - Extra provider specific information about the endpoint
  for use in the `[Interface]` section of client configs (see below).
- `instance.public_key` - Endpoint public key
- `instance.ip` - Public IP of the instance
- `instance.port` - Port where wireguard listens on the instance

### Config

We can combine these outputs with a template file to generate a valid wireguard
config:

The template file contains a partial config, e.g. with your public key
already filled in. See
`tmpl.conf.example`:

```
[Interface]
Address = 192.168.78.2/24
${interface}
PrivateKey = 3ecEHBYaTaqXEr08MjYiwyPu8DBuk2LX5VPzHQPyxRw=
DNS = 1.1.1.1

PreUp = ./wg-vpn PreUp
PostUp = ./wg-vpn PostUp
PreDown = ./wg-vpn PreDown
PostDown = ./wg-vpn PostDown

[Peer]
PublicKey = ${endpoint_pubkey}
Endpoint = ${endpoint_ip}:${endpoint_port}
AllowedIPs = 0.0.0.0/0
```

In the third line, `interface` is a way for provider-specific changes to be
added to the template.
With GCP for example, the MTU needs to be altered.

### Complete example

Let's integrate the GCP endpoint provider with config generation along with using
`sops` to protect our client information:

```console
$ sops -d secrets.yaml
billing_account: XX-XX
region: us-east1
source_ranges:
- 2.2.2.2/32
peers: |
    PublicKey = cralfZjaxUU61lhBFuQAY4s0H6oIdNyyOKo1jxuY/hg=
    AllowedIPs = 192.168.78.2/32
```

```console
$ cat main.tf
variable "values_file" {
  type = string
}

locals {
  values = yamldecode(file(var.values_file))
}

module "init" {
  source = "https://github.com/michaelbeaumont/wireform//gcp/init"

  billing_account = local.values.billing_account
  region = local.values.region
}

module "instance" {
  source = "https://github.com/michaelbeaumont/wireform//gcp/instance"

  project_id = module.init.project_id
  subnetwork = module.init.subnetwork
  source_ranges = local.values.source_ranges
  peers = local.values.peers
}

output "conf" {
  value = templatefile("tmpl.conf.example", {
    interface = module.instance.interface_extra,
    endpoint_pubkey = module.instance.public_key,
    endpoint_ip = module.instance.ip,
    endpoint_port = module.instance.port,
  })
}
```

This can be executed with the following command:

```console
$ sops exec-file --no-fifo secrets.yaml 'terraform apply -var values_file={}'
```

The final, ready to use config can be retrieved with:

```console
$ terraform output conf
```
