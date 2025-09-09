output "host" {
  value       = module.redis.host
  description = "Redis host"
}

output "port" {
  value       = module.redis.port
  description = "Redis port"
}
