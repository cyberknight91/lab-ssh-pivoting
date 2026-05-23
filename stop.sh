#!/bin/bash
echo "[*] Parando el lab..."
sudo docker compose down
sudo docker network prune -f
echo "[+] Lab detenido."
