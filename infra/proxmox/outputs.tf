output "ct_ip" {
  description = "Container IP (DHCP)."
  value       = proxmox_virtual_environment_container.kursy.ipv4["eth0"]
}

output "app_url" {
  description = "Public app URL (Cloudflare Tunnel)."
  value       = "https://${var.public_domain}"
}

output "ssh_hint" {
  description = "Admin shell into the container."
  value       = "ssh root@${proxmox_virtual_environment_container.kursy.ipv4["eth0"]}"
}

output "superadmin_password" {
  description = "Fresh-install fallback superadmin password (init-mongo.js on an empty db). Not the password of migrated data - reset that one separately (README.md)."
  value       = random_password.superadmin.result
  sensitive   = true
}
