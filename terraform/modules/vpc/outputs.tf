output "network_id" {
  value = module.vpc.network_id
}

output "network_name" {
  value = module.vpc.network_name
}

output "pub_sub_network_name" {
  value = local.pub_sub_network_name
}

output "priv_sub_network_name" {
  value = local.priv_sub_network_name
}

output "network_self_link" {
  value = module.vpc.network_self_link
}
