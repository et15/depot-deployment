# Skeleton for docker compose project

- stores secrets encrypted with SOPS
- script for `docker compose up` with env file provision with decrypted secrets
- template for service file, softlink from `/etc/systemd/system/`
