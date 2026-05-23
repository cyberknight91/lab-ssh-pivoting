# Lab SSH — Pivoting, Port Forwarding y SOCKS5
**CyberKnight · Video 07 · Curso Linux para Ciberseguridad**

Lab de Docker para practicar SSH tunneling, port forwarding y proxying con SOCKS5 en un entorno de red aislado.

---

## Requisitos

- Docker instalado
- Docker Compose v2 (`docker compose version`)

### Instalar Docker Compose si no está disponible

```bash
mkdir -p ~/.docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" \
     -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
```

---

## Levantar el lab

```bash
git clone https://github.com/cyberknight91/lab-ssh-pivoting.git
cd lab-ssh-pivoting
sudo docker compose up -d --build
```

Verificar que los 4 contenedores están corriendo:

```bash
sudo docker compose ps
```

---

## Entrar al entorno atacante

Todas las prácticas se hacen desde dentro del contenedor `atacante`:

```bash
sudo docker exec -it atacante bash
```

---

## Arquitectura

```
          RED EXTERNA (172.28.0.0/24)
┌─────────────────────────────────────────┐
│  [atacante]          [servidor-dmz]     │
│  172.28.0.100        172.28.0.10        │
└──────────────────────────┬──────────────┘
                           │
          RED INTERNA (10.10.0.0/24)  ← atacante NO llega aquí
┌──────────────────────────┼──────────────┐
│                     10.10.0.2           │
│            ┌────────────┴──────────┐    │
│     [web-interno]           [db-interna]│
│       10.10.0.5:80           10.10.0.10 │
└─────────────────────────────────────────┘
```

---

## Credenciales

| Servicio | IP           | Usuario | Contraseña |
|----------|--------------|---------|------------|
| SSH DMZ  | 172.28.0.10  | pivot   | pivot123   |
| MySQL    | 10.10.0.10   | lab     | lab123     |
| Web      | 10.10.0.5:80 | —       | —          |

---

## Comandos del lab

```bash
# SSH básico
ssh pivot@172.28.0.10

# Local forwarding — web interna
ssh -L 8080:10.10.0.5:80 pivot@172.28.0.10

# Local forwarding — MySQL interna
ssh -L 3307:10.10.0.10:3306 pivot@172.28.0.10

# Remote forwarding
ssh -R 9090:localhost:9090 pivot@172.28.0.10

# SOCKS5 + ProxyChains
ssh -D 1080 -N -f pivot@172.28.0.10
proxychains curl http://10.10.0.5/
proxychains nmap -sT -Pn -p 80,3306 10.10.0.5
```

Guía completa paso a paso: [LAB_VIDEO07.md](LAB_VIDEO07.md)

---

## Parar el lab

```bash
sudo docker compose down
```
