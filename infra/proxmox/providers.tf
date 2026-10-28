# kursy (INGInious) on Proxmox: provider configuration.

provider "proxmox" {
  endpoint  = var.pm_endpoint
  api_token = var.pm_api_token
  insecure  = var.pm_insecure

  # Node-level SSH access (agent-based) as a fallback channel for provider
  # operations; primary provisioning goes through the PVE REST API.
  ssh {
    agent    = true
    username = "root"
  }
}
