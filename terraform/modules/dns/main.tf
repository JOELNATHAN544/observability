module "dns-public-zone" {
  source  = "terraform-google-modules/cloud-dns/google"
  version = "~> 5.0"

  project_id = var.project_id
  type       = "public"
  name       = local.zone_name
  domain     = "${var.root_domain_name}."
  labels     = var.labels
  private_visibility_config_networks = [var.network_self_link]

  recordsets = [
    {
      name = "*"
      type = "A"
      ttl  = 300
      records = [
        var.ip_address,
      ]
    },
    {
      name = ""
      type = "A"
      ttl  = 300
      records = [
        var.ip_address,
      ]
    },
  ]
}
