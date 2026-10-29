# kursy.dinocoders.pl (INGInious) na Proxmox

Terraform-managed kontener LXC z pełnym produkcyjnym stackiem INGInious,
wystawiony publicznie przez **Cloudflare Tunnel** (wzorzec: czytojebnie i
dayveer `infra/proxmox`).

## Architektura

```
Internet ──https──> serveo.net (TLS termination, Let's Encrypt za domenę)
                      |  autossh reverse tunnel (systemd serveo.service)
                      |  wymaga: Route53 CNAME kursy.dinocoders.pl -> serveo.net
                      v
LXC Debian 12 (unprivileged, nesting) na pve / local-lvm / vmbr0 / DHCP
  Docker Compose (/opt/kursy):
    env-base / env-default / env-python3   obrazy gradingowe (label
                                           org.inginious.grading.name)
    db        mongo:6.0.2                  /opt/kursy/db (WiredTiger)
    backend   kolejkowanie submisji
    agent-docker grading przez docker.sock (kontenery rodzeństwo)
    agent-mcq     grading quizów
    frontend  webapp
    webdav    /dav/*
    caddy     plain HTTP na 127.0.0.1:8080 (tunel celuje tutaj)
  systemd serveo.service (wzorzec: minecraft.dinocoders.pl)
```

Obrazy buduje GitHub Actions (`.github/workflows/docker-images.yml`) i pushuje
do `ghcr.io/bgruszka/inginious/*` (tagi `latest` + `main-<sha>`).

## Różnice względem czytojebnie

- 8 obrazów zamiast 2 (core + env gradingowe); env-* są wykrywane przez
  labelkę, nie po ścieżce registry.
- Stack startuje dopiero po migracji danych: bootstrap szuka pliku-znacznika
  `/opt/kursy/.data-loaded` (mongodump + tasks/ z laptopa, patrz niżej).
- Sekrety aplikacyjne (`session_secret`, `api_jwt_secret`) są w tfvars —
  muszą być identyczne jak na laptopie, żeby sesje i tokeny API przetrwały
  migrację.
- Node PVE ma mało RAM (~7 GB, 10+ gości) — CT ma 2 GB RAM + 2 GB swap.

## Wymagania (one-time)

1. **Proxmox API token** — ten sam co w homelab/czytojebnie.
2. **GitHub PAT** z `read:packages` — jak w czytojebnie.
3. **DNS**: w strefie `dinocoders.pl` (Route53, konto AWS posiadające strefę)
   dodaj rekord: `kursy` `CNAME` → `serveo.net` (TTL 300). Bez tego serveo
   odrzuca bind tunelu (`remote port forwarding failed`); autossh ponawia
   co 10 s, więc rekord podłapie się automatycznie po dodaniu.
4. **Cloudflare (opcjonalny upgrade)**: przeniesienie strefy na CF + tunel
   zamiast serveo - patrz historia w git; template `kursy-cloudflared` został.
5. Lokalnie: `terraform` (>= 1.6).

## Deploy

```bash
cp infra/proxmox/terraform.tfvars.example infra/proxmox/terraform.tfvars
# wypełnij: pm_api_token, ghcr_pat, session_secret, api_jwt_secret
make proxmox-init
make proxmox-apply          # provisionuje CT + bootstrap (pull obrazów)
```

Po pierwszym apply stack **nie startuje** — najpierw migracja danych:

```bash
# na laptopie (lokalny stack musi działać):
docker exec inginious-db-1 mongodump --archive --gzip --db INGInious \
  > /tmp/inginious-dump.arch.gz
IP=$(cd infra/proxmox && terraform output -raw ct_ip)
rsync -a tasks/ root@$IP:/opt/kursy/tasks/
scp /tmp/inginious-dump.arch.gz root@$IP:
ssh root@$IP '
  mkdir -p /opt/kursy/db && chown -R 999:999 /opt/kursy/db 2>/dev/null || true
  cd /opt/kursy && docker compose up -d db
  sleep 15
  docker exec -i kursy-db-1 mongorestore --archive --gzip --drop < /inginious-dump.arch.gz
  touch /opt/kursy/.data-loaded
  docker compose up -d
'
```

Apply wypisuje IP kontenera (`terraform output ct_ip`).

**Reset hasła superadmina** (dane po migracji mają stary hash `superadmin`):

```bash
PW='<nowe-haslo>'
ssh root@$IP "docker exec kursy-frontend-1 python3 -c \"
from argon2 import PasswordHasher
from inginious.common.mongo import MongoManager
\""
# ... albo prosto przez mongosh (hash policzony w kontenerze frontend):
HASH=$(ssh root@$IP "docker exec kursy-frontend-1 python3 -c \"
from argon2 import PasswordHasher; print(PasswordHasher().hash('$PW'))\"")
ssh root@$IP "docker exec kursy-db-1 mongosh INGInious --eval \"
db.users.updateOne({username:'superadmin'}, {\$set:{password:'argon2id-$HASH'}})\""
```

## Redeploy nowej wersji aplikacji

```bash
git push                     # Actions buduje obrazy latest + main-<sha>
make proxmox-redeploy TAG=main-<sha>   # albo TAG=latest
```

## Diagnostyka

```bash
make proxmox-status          # docker compose ps + stan tunelu
make proxmox-logs            # logi aplikacji
ssh root@$(cd infra/proxmox && terraform output -raw ct_ip)
curl http://$(cd infra/proxmox && terraform output -raw ct_ip):8080  # (LAN; port jest na 127.0.0.1 CT)
```

Uwaga: caddy binduje się na `127.0.0.1:8080` wewnątrz CT — z laptopa smoke
test zrób przez `ssh -L 8080:127.0.0.1:8080 root@$IP` i otwórz
http://localhost:8080.

## Troubleshooting

- **Thin pool `local-lvm` na nodzie jest mały (~66 GB) i współdzielony z 10+
  gośćmi** — obrazy INGInious zajmują ~5-6 GB realnego miejsca. Bootstrap
  capuje logi kontenerów (daemon.json) i prunuje stare obrazy; nie podbijaj
  `ct_disk_gb` bez sprawdzenia `avail` w API storage (przy 0 wolnego inne
  goście dostają I/O errors). Rozbudowa puli wymaga dostępu do hosta PVE.
- **HTTP 595 / "Connection refused" przy pobieraniu szablonu Debiana** —
  nie dotyczy: `lxc_template_volid` wskazuje szablon już obecny na datastore.
- **docker compose pull fails 401** — PAT w `.ghcr-pat` bez `read:packages`.
- **Mongo nie wstaje (Illegal instruction)** — CPU nodu bez AVX; MongoDB 6
  wymaga AVX. Nodule sprawdź: `lscpu | grep avx` na PVE.
- **OOM na nodzie** — goście na PVE są overcommited; przy problemach zmniejsz
  `ct_memory_mb` albo zatrzymaj inne duże goście (np. minecraft).

## `make proxmox-destroy`

Niszczy kontener **razem z wolumenem bazy i zadaniami** (punktacja bezpowrotnie).
