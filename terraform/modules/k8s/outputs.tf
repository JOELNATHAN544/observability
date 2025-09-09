output "cluster_endpoint" {
  value = "https://${module.gke.endpoint}"
}

output "cluster_ca" {
  value = module.gke.ca_certificate
}

output "name" {
  value = module.gke.name
}