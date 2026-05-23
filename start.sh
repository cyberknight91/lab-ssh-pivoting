#!/bin/bash
set -e

echo "[*] Levantando el lab..."
sudo docker compose up -d --build

echo "[*] Eliminando ruta directa a la red interna..."
sleep 2
sudo ip route del 10.10.0.0/24 2>/dev/null || true

echo ""
echo "[*] Verificando aislamiento..."
if curl -s --max-time 2 http://10.10.0.5 > /dev/null 2>&1; then
    echo "[!] AVISO: el host aún llega a la red interna — reinicia el lab"
else
    echo "[+] Aislamiento OK — el host no llega a 10.10.0.5"
fi

if ping -c 1 -W 1 172.28.0.10 > /dev/null 2>&1; then
    echo "[+] DMZ alcanzable en 172.28.0.10"
fi

echo ""
echo "Lab listo. Credenciales:"
echo "  SSH DMZ  →  ssh pivot@172.28.0.10  (pivot123)"
echo "  Web      →  10.10.0.5:80"
echo "  MySQL    →  10.10.0.10:3306  (lab / lab123)"
