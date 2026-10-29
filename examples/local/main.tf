variable "port" {
  type    = number
  default = 2222
}

# Leave it unset to run without a key. CI sets it with TF_VAR_api_key.
variable "api_key" {
  type      = string
  default   = null
  sensitive = true
}

module "qdrant" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  api_key = var.api_key
}

output "urls" {
  value = module.qdrant.urls
}
