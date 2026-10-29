# Facts give each host's architecture, which picks the release tarball.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(keys(var.checksums), self.arch)
      error_message = "Host ${each.key} is ${self.arch}. The circuit has Qdrant builds for ${join(" and ", keys(var.checksums))}."
    }
  }
}

locals {
  home   = "/var/lib/qdrant"
  dir    = "/opt/qdrant/${var.qdrant_version}"
  binary = "${local.dir}/qdrant"
  config = "/etc/qdrant/config.yaml"

  # Where the host itself reaches the REST API.
  local_host = lookup({ "0.0.0.0" = "127.0.0.1", "::" = "[::1]" }, var.listen_address, strcontains(var.listen_address, ":") ? "[${var.listen_address}]" : var.listen_address)
  local_url  = "http://${local.local_host}:${var.http_port}"

  # The musl builds are static, so one binary runs on every distribution
  # whatever its glibc.
  tarball = { for name, f in data.conn3x_host.facts : name => "qdrant-${f.arch}-unknown-linux-musl.tar.gz" }

  # Qdrant reads YAML, and JSON strings are YAML strings, so jsonencode
  # quotes paths and the key safely.
  config_base = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    storage:
      storage_path: ${jsonencode(var.storage_path)}
      snapshots_path: ${jsonencode(var.snapshots_path)}
    telemetry_disabled: ${var.telemetry_disabled}
    service:
      host: ${jsonencode(var.listen_address)}
      http_port: ${var.http_port}
      grpc_port: ${var.grpc_port}
  EOT
}

circuit "qdrant" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Minimal images can lack any of these.
  step "tools" {
    for_each = toset(["curl", "tar", "gzip"])
    package {
      name = item.value
    }
  }

  step "user" {
    user {
      name   = "qdrant"
      system = true
      home   = local.home
      shell  = "/usr/sbin/nologin"
    }
  }

  step "dirs" {
    for_each = toset([local.home, var.storage_path, var.snapshots_path])
    directory {
      path  = item.value
      owner = "qdrant"
      group = "qdrant"
      mode  = "0750"
    }
  }

  step "release_dir" {
    directory {
      path = local.dir
    }
  }

  step "download" {
    download {
      url    = "https://github.com/qdrant/qdrant/releases/download/v${var.qdrant_version}/${local.tarball[each.key]}"
      sha256 = var.checksums[data.conn3x_host.facts[each.key].arch]
      dest   = "${local.dir}/${local.tarball[each.key]}"
    }
  }

  step "unpack" {
    archive {
      src     = "${local.dir}/${local.tarball[each.key]}"
      dest    = local.dir
      creates = local.binary
    }
  }

  step "config_dir" {
    directory {
      path  = "/etc/qdrant"
      owner = "root"
      group = "qdrant"
      mode  = "0750"
    }
  }

  # The file can hold the api_key, so it's write-only: the key stays out of
  # the plan and state, which record only an HMAC of the content.
  step "config" {
    file {
      path       = local.config
      content_wo = var.api_key == null ? local.config_base : "${local.config_base}  api_key: ${jsonencode(var.api_key)}\n"
      owner      = "qdrant"
      group      = "qdrant"
      mode       = "0600"
    }
    notify = [handler.restart]
  }

  # Qdrant looks for config/ under its working directory before reading
  # --config-path, so it runs from its home, where there is none.
  step "unit" {
    file {
      path    = "/etc/systemd/system/qdrant.service"
      content = <<-EOT
        [Unit]
        Description=Qdrant vector database
        After=network-online.target
        Wants=network-online.target

        [Service]
        User=qdrant
        Group=qdrant
        WorkingDirectory=${local.home}
        ExecStart=${local.binary} --config-path ${local.config}
        Restart=on-failure
        LimitNOFILE=65535
        NoNewPrivileges=true
        ProtectSystem=strict
        ProtectHome=true
        PrivateTmp=true
        ReadWritePaths=${join(" ", distinct([local.home, var.storage_path, var.snapshots_path]))}

        [Install]
        WantedBy=multi-user.target
      EOT
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "qdrant"
      state   = "started"
      enabled = true
    }
  }

  # Qdrant ignores a SIGTERM that comes in the moment it opens its port,
  # until systemd kills it 90 seconds later. Waiting for /readyz, which
  # needs no api_key, keeps the handler's restart on a first apply out of
  # that window.
  step "ready" {
    command {
      command = "for _ in $(seq 120); do curl -sf -o /dev/null ${local.local_url}/readyz && exit 0; sleep 1; done; exit 1"
      unless  = "curl -sf -o /dev/null ${local.local_url}/readyz"
    }
  }

  handler "restart" {
    service {
      name = "qdrant"
    }
  }
}
