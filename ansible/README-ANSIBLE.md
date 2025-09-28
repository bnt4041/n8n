# Despliegue Automático n8n con Ansible

Este playbook instala y configura:

1. Stack LAMP mínimo (Apache + PHP) para servir como proxy y mantener compatibilidad con apps existentes.
2. Docker + Docker Compose plugin.
3. Clona este repositorio en `/var/www/html/n8n`.
4. Genera `.env` para n8n a partir de plantilla.
5. Configura VirtualHost Apache (`proxy` a n8n en puerto 5678).
6. Crea unidad systemd `n8n-stack.service` para arranque automático.
7. Levanta los contenedores (`docker compose up -d`).
8. (Opcional) Emite certificado Let’s Encrypt y activa HTTPS automático cuando `enable_https=true`.

## Requisitos

- Control machine: Ansible >= 2.15
- Servidor destino: Debian 11/12 o RHEL/CentOS/Alma/Rocky 8/9
- Acceso SSH con privilegios sudo/root

## Archivos principales

- `deploy-n8n.yml`: Playbook principal
- `inventory.ini`: Ejemplo de inventario
- `templates/n8n.env.j2`: Variables de entorno n8n
- `templates/n8n-vhost.conf.j2`: VirtualHost Apache

## Variables importantes

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `n8n_domain` | Dominio público para acceder a n8n | example.com |
| `n8n_db_password` | Password DB Postgres n8n | CHANGEME_DB_PASS |
| `n8n_basic_auth_password` | Password autenticación básica UI | CHANGEME_UI_PASS |
| `enable_https` | Si `true`, emite certificado Let’s Encrypt y fuerza redirección HTTPS | false |
| `certbot_email` | Email registro ACME (términos Let’s Encrypt) | admin@example.com |

Ejemplo sobrescritura en línea:

```
--extra-vars "n8n_domain=automatiza.tu-dominio.com n8n_db_password=SuperSegura123 n8n_basic_auth_password=OtraClaveSegura enable_https=true certbot_email=ops@tu-dominio.com"
```

## Ejecución básica

```
ansible-playbook -i inventory.ini deploy-n8n.yml \
  --extra-vars "n8n_domain=tu-dominio.com n8n_db_password=DB_PASS n8n_basic_auth_password=UI_PASS"
```

## Comprobar servicio

```
systemctl status n8n-stack
journalctl -u n8n-stack -f
```

## Actualizar n8n

1. Edita `docker-compose.yml` (imagen n8nio/n8n:tag nueva) en el repo.
2. Re-ejecuta el playbook (para pull) o entra a la ruta y:
   ```
   docker compose pull
   docker compose up -d
   ```

## HTTPS Automático (Let’s Encrypt)

Si ejecutas el playbook con `enable_https=true`:

1. Instala Certbot y módulo Apache correspondiente.
2. Genera/renueva certificado para `n8n_domain`.
3. Activa VirtualHost con bloque :443 y redirección 80 -> 443.
4. Ajusta plantilla `.env` (usa `N8N_PROTOCOL=https`).

Ejemplo:

```
ansible-playbook -i inventory.ini deploy-n8n.yml \
  --extra-vars "n8n_domain=tu-dominio.com n8n_db_password=DB_PASS n8n_basic_auth_password=UI_PASS enable_https=true certbot_email=admin@tu-dominio.com"
```

Renovación: Certbot instala un cron/systemd timer que renueva automáticamente; no necesitas añadir tarea extra.

## Rollback

Si la nueva versión falla:
1. Cambia a la etiqueta anterior en `docker-compose.yml`.
2. `docker compose up -d`.
3. Restaura backups si es necesario.

## Backups recomendados

- Dump Postgres (usa instrucciones del README principal)
- Volumen de datos n8n

## Notas

- Considera añadir firewall (UFW/firewalld) permitiendo solo 22,80,443.
- Para alta disponibilidad: separar instancia principal / workers y agregar Redis + escalado horizontal.
- Si cambias el dominio, vuelve a ejecutar el playbook con `enable_https=true` para reemitir certificados.

---
