locals {
  name                  = "${var.name}-vpc"
  pub_sub_network_name  = "${local.name}-subnet-01"
  priv_sub_network_name = "${local.name}-subnet-02"
}