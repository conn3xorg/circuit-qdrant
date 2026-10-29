variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "qdrant_version" {
  type        = string
  default     = "1.20.0"
  description = "Qdrant release to install, without the leading v."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.qdrant_version))
    error_message = "qdrant_version must be a release number such as \"1.20.0\", without the leading v."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the musl release tarball for each architecture, x86_64 and aarch64, from the release page. Change these with qdrant_version."
  default = {
    x86_64  = "b03a64616a1f41ddab78b480a318466541765f19835318113b1821cbea8df52c"
    aarch64 = "bd8a458b8ef8006ce2c603c5bd6d1d973e39d787f794008dd959112e747c3bb7"
  }

  validation {
    condition     = alltrue([for a, c in var.checksums : contains(["x86_64", "aarch64"], a) && can(regex("^[0-9a-f]{64}$", c))])
    error_message = "checksums maps x86_64 or aarch64 to a SHA-256 in lowercase hex."
  }
}

variable "listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address the REST and gRPC APIs listen on. The default keeps Qdrant to the host itself; \"0.0.0.0\" listens on every address."

  validation {
    condition     = can(cidrhost("${var.listen_address}/${strcontains(var.listen_address, ":") ? 128 : 32}", 0))
    error_message = "listen_address must be an IP address, such as \"127.0.0.1\" or \"0.0.0.0\"."
  }
}

variable "http_port" {
  type        = number
  default     = 6333
  description = "Port of the REST API."

  validation {
    condition     = var.http_port >= 1 && var.http_port <= 65535 && floor(var.http_port) == var.http_port
    error_message = "http_port must be a port number from 1 to 65535."
  }
}

variable "grpc_port" {
  type        = number
  default     = 6334
  description = "Port of the gRPC API."

  validation {
    condition     = var.grpc_port >= 1 && var.grpc_port <= 65535 && floor(var.grpc_port) == var.grpc_port
    error_message = "grpc_port must be a port number from 1 to 65535."
  }
}

variable "api_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Key every API request must send in an api-key header. When null, the APIs take requests without one. Pass it at run time with -var or TF_VAR_api_key; it never reaches state."

  validation {
    condition     = var.api_key == null || length(coalesce(var.api_key, "-")) >= 16
    error_message = "api_key must be at least 16 characters."
  }
}

variable "storage_path" {
  type        = string
  default     = "/var/lib/qdrant/storage"
  description = "Directory Qdrant keeps its collections in."

  validation {
    condition     = startswith(var.storage_path, "/") && !strcontains(var.storage_path, "\n") && !strcontains(var.storage_path, " ")
    error_message = "storage_path must be an absolute path without spaces."
  }
}

variable "snapshots_path" {
  type        = string
  default     = "/var/lib/qdrant/snapshots"
  description = "Directory Qdrant writes snapshots to."

  validation {
    condition     = startswith(var.snapshots_path, "/") && !strcontains(var.snapshots_path, "\n") && !strcontains(var.snapshots_path, " ")
    error_message = "snapshots_path must be an absolute path without spaces."
  }
}

variable "telemetry_disabled" {
  type        = bool
  default     = true
  description = "Stop Qdrant sending anonymous usage statistics to its developers. Set false to send them."
}
