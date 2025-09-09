output "dns_ns" {
  value       = try(module.dns[0].name_servers, null)
  description = "The Zone NS"
}

output "ip_address" {
  value       = module.ip.address
  description = "IP Address"
}