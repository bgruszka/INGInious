# Inputs for the kursy (INGInious) Proxmox deployment.
# Copy terraform.tfvars.example to terraform.tfvars (gitignored) and fill in.

# --- Proxmox API -------------------------------------------------------------
variable "pm_endpoint" {
  description = "Proxmox VE API endpoint."
  type        = string
  default     = "https://192.168.68.50:8006/"
}

variable "pm_api_token" {
  description = "API token as USER@pam!TOKENID=SECRET (needs privileges to create LXC)."
  type        = string
  sensitive   = true
}

variable "pm_node" {
  description = "PVE node name."
  type        = string
  default     = "proxmox"
}

variable "pm_insecure" {
  description = "Skip TLS verification (self-signed cert on the PVE host)."
  type        = bool
  default     = true
}

# --- Container spec ----------------------------------------------------------
# Node RAM is tight (~7 GB total, shared with 10 other guests), so the default
# is modest: INGInious idles at ~1 GB; grading spikes land in swap if needed.
variable "ct_vmid" {
  description = "LXC VMID on the node."
  type        = number
  default     = 216
}

variable "ct_hostname" {
  description = "Container hostname."
  type        = string
  default     = "kursy"
}

variable "ct_bridge" {
  description = "Network bridge."
  type        = string
  default     = "vmbr0"
}

variable "ct_storage" {
  description = "Datastore for the container root disk (lvmthin: virtual size may exceed pool free space)."
  type        = string
  default     = "local-lvm"
}

variable "ct_cores" {
  description = "Allocated CPU cores."
  type        = number
  default     = 4
}

variable "ct_memory_mb" {
  description = "Dedicated memory in MB."
  type        = number
  default     = 2048
}

variable "ct_swap_mb" {
  description = "Swap in MB (absorbs grading spikes; node RAM is overcommitted)."
  type        = number
  default     = 2048
}

variable "ct_disk_gb" {
  description = "Root disk size in GB."
  type        = number
  default     = 16
}

variable "lxc_template_volid" {
  description = "Existing Debian 12 template volid on the node (no download needed)."
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
}

# --- SSH access to the container --------------------------------------------
variable "ssh_public_key_path" {
  description = "Path to YOUR public key injected into the container for admin access."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Matching private key, used by the terraform SSH provisioners."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# --- Images -------------------------------------------------------------------
variable "ghcr_registry" {
  description = "GHCR registry namespace the workflow pushes to."
  type        = string
  default     = "ghcr.io/bgruszka"
}

variable "ghcr_user" {
  description = "GHCR login username."
  type        = string
  default     = "bgruszka"
}

variable "ghcr_pat" {
  description = "GitHub PAT with read:packages scope (fork is public but packages may be private)."
  type        = string
  sensitive   = true
}

variable "image_tag" {
  description = "Image tag from the docker-images workflow (latest or main-<sha>)."
  type        = string
  default     = "latest"
}

# --- INGInious application secrets -------------------------------------------
# Keep these stable across applies: the session secret keeps existing logins
# alive and the JWT secret keeps API tokens valid across redeploys.
variable "session_secret" {
  description = "INGInious session_parameters.secret_key."
  type        = string
  sensitive   = true
}

variable "api_jwt_secret" {
  description = "INGInious api_jwt_secret."
  type        = string
  sensitive   = true
}

variable "public_domain" {
  description = "Public hostname served through the Cloudflare tunnel."
  type        = string
  default     = "kursy.dinocoders.pl"
}

variable "web_bind_port" {
  description = "Loopback port on the container that the tunnel targets."
  type        = number
  default     = 8080
}

# --- Cloudflare ---------------------------------------------------------------
variable "cloudflare_tunnel_token" {
  description = "Token of the Cloudflare tunnel (from `cloudflared service install`). Empty = tunnel service not installed."
  type        = string
  sensitive   = true
  default     = ""
}
