# Script de despliegue n8n (Ubuntu 24.04)

Script: `deploy_n8n.sh`

## Funcionalidad
Instala y configura en un servidor limpio Ubuntu 24.04:

- LAMP (Apache, MariaDB, PHP) – solicitado aunque n8n no lo requiere para funcionar
- Docker + Docker Compose plugin
- Clona/actualiza este repositorio en `/var/www/html/n8n`
- VirtualHost Apache que hace proxy al contenedor n8n
- SSL opcional con Let's Encrypt (Certbot)
- Servicio systemd para levantar el stack en cada arranque
- Levanta contenedores n8n + Postgres definidos en `docker-compose.yml`

## Requisitos previos
- Servidor Ubuntu 24.04 con acceso root (o sudo)
- Dominio apuntando (A / AAAA) a la IP del servidor si se usará `--ssl`

## Uso

```bash
sudo bash scripts/deploy_n8n.sh --domain n8n.tu-dominio.com
```

Con SSL:

```bash
sudo bash scripts/deploy_n8n.sh --domain n8n.playhunt.es --ssl --email beni4041@gmail.com
```

Argumentos:
- `--domain` (obligatorio)
- `--ssl` habilita emisión de certificado
- `--email` requerido si usas `--ssl`
- `--repo` para cambiar la URL del repositorio (por defecto origin GitHub)

## Directorios
- Código/repositorio: `/var/www/html/n8n`
- VirtualHost Apache: `/etc/apache2/sites-available/n8n.conf`
- Servicio systemd: `/etc/systemd/system/n8n-docker.service`

## Comandos útiles

Ver estado del servicio:
```bash
systemctl status n8n-docker.service
```

Reiniciar stack:
```bash
sudo systemctl restart n8n-docker.service
```

Logs n8n:
```bash
cd /var/www/html/n8n
docker compose logs -f n8n
```

Actualizar a última versión del repo / imágenes:
```bash
cd /var/www/html/n8n
git pull --ff-only
docker compose pull
docker compose up -d
```

## Notas de seguridad
- Cambia las contraseñas generadas en `.env` si es necesario.
- Activa autenticación básica n8n si se expone públicamente (`N8N_BASIC_AUTH_ACTIVE=true`).
- Usa firewall (ufw) permitiendo solo 80/443 y SSH.

## Eliminación del stack
```bash
systemctl stop n8n-docker.service
cd /var/www/html/n8n
docker compose down
```
(Elimina volúmenes sólo si estás seguro: `docker compose down -v`)

## Roadmap opcional
- Añadir Redis para colas.
- Separar worker/webhook containers.
- Integrar Traefik en lugar de Apache.
