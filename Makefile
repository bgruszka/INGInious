# kursy (INGInious) on Proxmox - targets (wzorzec: czytojebnie/Makefile).

PROXMOX_TF_DIR := infra/proxmox

.PHONY: help proxmox-init proxmox-plan proxmox-apply proxmox-redeploy proxmox-status proxmox-logs proxmox-destroy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v '^#' | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

proxmox-init: ## terraform init for the Proxmox stack
	cd $(PROXMOX_TF_DIR) && terraform init

proxmox-plan: ## terraform plan (needs terraform.tfvars)
	cd $(PROXMOX_TF_DIR) && terraform plan

proxmox-apply: ## Provision CT + bootstrap stack (starts only after data migration marker exists)
	cd $(PROXMOX_TF_DIR) && terraform apply

proxmox-redeploy: ## Redeploy app images: make proxmox-redeploy TAG=main-abcd123
	# -replace forces the bootstrap (pull + up) even when the tag did not
	# change (e.g. TAG=latest re-pushed with new image content).
	cd $(PROXMOX_TF_DIR) && terraform apply -auto-approve -replace="null_resource.bootstrap" -var=image_tag=$(TAG)

proxmox-status: ## Stack status on the container
	IP=$$(cd $(PROXMOX_TF_DIR) && terraform output -raw ct_ip) && \
	ssh "root@$${IP}" 'cd /opt/kursy && docker compose ps && echo "--- tunnel ---" && (systemctl is-active kursy-cloudflared || true)'

proxmox-logs: ## Tail application logs on the container
	IP=$$(cd $(PROXMOX_TF_DIR) && terraform output -raw ct_ip) && \
	ssh "root@$${IP}" 'cd /opt/kursy && docker compose logs -f --tail=100'

proxmox-destroy: ## Tear the whole thing down (destroys the mongo volume and tasks!)
	cd $(PROXMOX_TF_DIR) && terraform destroy
