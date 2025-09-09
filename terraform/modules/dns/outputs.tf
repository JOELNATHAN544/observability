output "name_servers" {
  value = module.dns-public-zone.name_servers
  description = "The Zone NS"
}
