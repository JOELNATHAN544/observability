output "buckets_map" {
  value = module.gcs_buckets.buckets_map
}

output "access_ids" {
  value = {
    for idx, name in var.names :name =>
    module.gcs_buckets.hmac_keys[0][module.service_accounts.service_accounts_map[name].email].access_id
  }
}

output "secrets" {
  value = {
    for idx, name in var.names :name =>
    module.gcs_buckets.hmac_keys[0][module.service_accounts.service_accounts_map[name].email].secret
  }
}