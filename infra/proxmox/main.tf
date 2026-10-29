# kursy (INGInious) on Proxmox: LXC container + Docker stack + Cloudflare Tunnel.
# Pattern: czytojebnie/infra/proxmox.
#
# What apply does:
#   1. Creates an unprivileged Debian 12 container (nesting for Docker), DHCP.
#   2. Renders compose/configuration/caddy/cloudflared files and uploads them
#      over SSH.
#   3. Bootstraps: installs Docker + cloudflared, logs into GHCR, pulls images.
#   4. Starts the stack only once /opt/kursy/.data-loaded exists - the mongo
#      dump and tasks/ from the laptop must be restored first (README.md).
#
# Secrets (session_secret, api_jwt_secret, ghcr_pat, CF tunnel token) are
# sensitive tfvars and end up in the local tfstate - do not commit *.tfstate*.

# Fresh-install fallback password for the superadmin user (created by
# deploy/init-mongo.js on an empty db). After restoring migrated data, reset
# the real superadmin password - see README.md.
resource "random_password" "superadmin" {
  length  = 24
  special = false
}

resource "proxmox_virtual_environment_container" "kursy" {
  node_name    = var.pm_node
  vm_id        = var.ct_vmid
  description  = "kursy.dinocoders.pl - INGInious (terraform-managed)"
  tags         = ["kursy", "inginious", "terraform"]
  unprivileged = true
  started      = true

  cpu {
    cores = var.ct_cores
  }

  memory {
    dedicated = var.ct_memory_mb
    swap      = var.ct_swap_mb
  }

  disk {
    datastore_id = var.ct_storage
    size         = var.ct_disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.ct_bridge
  }

  features {
    # Docker inside an unprivileged CT needs nesting only (same as
    # czytojebnie/dayveer); keyctl stays omitted on purpose.
    nesting = true
  }

  initialization {
    hostname = var.ct_hostname

    user_account {
      keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  operating_system {
    template_file_id = var.lxc_template_volid
    type             = "debian"
  }

  lifecycle {
    # Recreating the container would wipe the mongo volume and tasks; never
    # do it implicitly.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Bootstrap / redeploy. Re-runs when config files, secrets, the CF tunnel
# token or image_tag change.
# ---------------------------------------------------------------------------
resource "null_resource" "bootstrap" {
  triggers = {
    container_id   = proxmox_virtual_environment_container.kursy.id
    image_tag      = var.image_tag
    compose_sha    = filemd5("${path.module}/templates/docker-compose.prod.yml.tftpl")
    conf_sha       = filemd5("${path.module}/templates/configuration.yaml.tftpl")
    caddy_sha      = filemd5("${path.module}/templates/caddy.prod.tftpl")
    bootstrap_sha  = filemd5("${path.module}/templates/bootstrap.sh.tftpl")
    cf_tunnel_sha  = filemd5("${path.module}/templates/kursy-cloudflared.service.tftpl")
    session_secret = var.session_secret
    api_jwt_secret = var.api_jwt_secret
    public_domain  = var.public_domain
    ghcr_pat       = var.ghcr_pat
  }

  connection {
    type        = "ssh"
    host        = proxmox_virtual_environment_container.kursy.ipv4["eth0"]
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /opt/kursy"]
  }

  # Application stack files.
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/docker-compose.prod.yml.tftpl",
      {
        ghcr_registry = var.ghcr_registry
        image_tag     = var.image_tag
        web_bind_port = var.web_bind_port
      }
    )
    destination = "/opt/kursy/docker-compose.yml"
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/configuration.yaml.tftpl",
      {
        session_secret = var.session_secret
        api_jwt_secret = var.api_jwt_secret
        public_domain  = var.public_domain
      }
    )
    destination = "/opt/kursy/configuration.yaml"
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/caddy.prod.tftpl",
      {
        web_bind_port = var.web_bind_port
      }
    )
    destination = "/opt/kursy/Caddyfile"
  }

  # MongoDB superadmin bootstrap script (runs only on an empty db).
  provisioner "file" {
    source      = "${path.module}/../../deploy/init-mongo.js"
    destination = "/opt/kursy/init-mongo.js"
  }

  # GHCR pull credentials for the images.
  provisioner "file" {
    content     = var.ghcr_pat
    destination = "/opt/kursy/.ghcr-pat"
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/bootstrap.sh.tftpl",
      {
        ghcr_user = var.ghcr_user
      }
    )
    destination = "/opt/kursy/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /opt/kursy/.ghcr-pat /opt/kursy/configuration.yaml",
      "chmod 700 /opt/kursy/bootstrap.sh",
      "/opt/kursy/bootstrap.sh",
    ]
  }
}

# Cloudflare tunnel unit (systemd, remotely-managed tunnel via token; ingress
# rules live in the Cloudflare Zero Trust dashboard). Skipped entirely until
# the token is filled in tfvars (see README: dinocoders.pl DNS first).
resource "null_resource" "tunnel" {
  count = var.cloudflare_tunnel_token != "" ? 1 : 0

  triggers = {
    container_id  = proxmox_virtual_environment_container.kursy.id
    cf_tunnel_sha = filemd5("${path.module}/templates/kursy-cloudflared.service.tftpl")
    cf_token      = var.cloudflare_tunnel_token
  }

  depends_on = [null_resource.bootstrap]

  connection {
    type        = "ssh"
    host        = proxmox_virtual_environment_container.kursy.ipv4["eth0"]
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/kursy-cloudflared.service.tftpl",
      {
        cloudflare_tunnel_token = var.cloudflare_tunnel_token
      }
    )
    destination = "/etc/systemd/system/kursy-cloudflared.service"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl daemon-reload",
      "systemctl enable --now kursy-cloudflared.service",
    ]
  }
}

# Public exposure via serveo.net (same pattern as minecraft.dinocoders.pl):
# Route53 CNAME kursy.dinocoders.pl -> serveo.net + autossh reverse forward
# to caddy on localhost:8080. TLS terminates at the serveo edge (Let's
# Encrypt for the custom domain). The cloudflared resource above stays as an
# optional future upgrade path.
resource "null_resource" "serveo_tunnel" {
  count = var.serveo_enabled ? 1 : 0

  triggers = {
    container_id    = proxmox_virtual_environment_container.kursy.id
    serveo_unit_sha = filemd5("${path.module}/templates/kursy-serveo.service.tftpl")
  }

  depends_on = [null_resource.bootstrap]

  connection {
    type        = "ssh"
    host        = proxmox_virtual_environment_container.kursy.ipv4["eth0"]
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get install -y -qq autossh >/dev/null",
      "[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -q",
    ]
  }

  provisioner "file" {
    content     = templatefile("${path.module}/templates/kursy-serveo.service.tftpl", {})
    destination = "/etc/systemd/system/serveo.service"
  }

  provisioner "remote-exec" {
    inline = [
      "systemctl daemon-reload",
      "systemctl enable --now serveo.service",
    ]
  }
}
