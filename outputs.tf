output "config_file" {
  description = "Path of the configuration file the circuit writes on each host."
  value       = "/etc/qdrant/config.yaml"
}

output "urls" {
  description = "Each host's REST API URL, by host name. With listen_address on every address, the host's own address; otherwise listen_address."
  value       = { for name, h in var.hosts : name => format(strcontains(local.url_host[name], ":") ? "http://[%s]:%d" : "http://%s:%d", local.url_host[name], var.http_port) }
}

locals {
  url_host = { for name, h in var.hosts : name => contains(["0.0.0.0", "::"], var.listen_address) ? try(h.address, h) : var.listen_address }
}
