#!/usr/bin/env bash
set -euo pipefail

# =============================================
# Script de despliegue n8n sobre Ubuntu 24.04
# Tareas:
#  - Instalar stack LAMP (Apache, MariaDB/MySQL, PHP) si no existe (aunque n8n no lo necesita se solicitó LAMP) 
#  - Instalar Docker + Docker Compose plugin si no está
#  - Clonar/actualizar repo n8n en /var/www/html/n8n (este repositorio)
#  - Configurar VirtualHost Apache apuntando a /var/www/html/n8n con proxy hacia contenedor n8n
#  - (Opcional) SSL con Certbot (Let's Encrypt) si se pasa --ssl
#  - Crear servicio systemd que asegure docker compose up al arranque
#  - Levantar contenedores n8n (usando docker-compose.yml del repo)
# =============================================

DOMAIN=""
EMAIL=""
ENABLE_SSL=false
REPO_URL="https://github.com/bnt4041/n8n.git"  # Ajustar si el remoto es privado
DEST_DIR="/var/www/html/n8n"
SYSTEMD_SERVICE="n8n-docker.service"
APACHE_CONF="/etc/apache2/sites-available/n8n.conf"
COMPOSE_CMD="docker compose"

export APACHE_LOG_DIR=/var/log/apache2

usage() {
  cat <<EOF
Uso: $0 --domain ejemplo.com [--ssl --email correo@dominio] [--repo URL]

Parámetros:
  --domain        Dominio o subdominio para acceder a n8n (obligatorio)
  --ssl           Solicitar certificado Let's Encrypt (requiere DNS apuntando al servidor)
  --email         Email de contacto para certbot (obligatorio si --ssl)
  --repo          URL del repositorio (por defecto: ${REPO_URL})
  --help          Mostrar esta ayuda

Ejemplos:
  $0 --domain automations.midominio.com
  $0 --domain n8n.midominio.com --ssl --email admin@midominio.com
EOF
}

check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "[ERROR] Ejecuta este script como root (sudo)." >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="$2"; shift 2 ;;
      --email)
        EMAIL="$2"; shift 2 ;;
      --ssl)
        ENABLE_SSL=true; shift ;;
      --repo)
        REPO_URL="$2"; shift 2 ;;
      --help|-h)
        usage; exit 0 ;;
      *)
        echo "Argumento no reconocido: $1" >&2; usage; exit 1 ;;
    esac
  done
  if [[ -z "$DOMAIN" ]]; then
    echo "[ERROR] --domain es obligatorio" >&2; exit 1
  fi
  if $ENABLE_SSL && [[ -z "$EMAIL" ]]; then
    echo "[ERROR] --email es obligatorio cuando se usa --ssl" >&2; exit 1
  fi
}

update_system() {
  echo "[INFO] Actualizando índice de paquetes..."
  apt-get update -y
}

install_lamp() {
  echo "[INFO] Verificando instalación LAMP..."
  local need_install=false
  command -v apache2 >/dev/null 2>&1 || need_install=true
  command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || need_install=true
  php -v >/dev/null 2>&1 || need_install=true
  if $need_install; then
    echo "[INFO] Instalando Apache, MariaDB y PHP básicos..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 mariadb-server php php-cli libapache2-mod-php
    systemctl enable apache2
    systemctl enable mariadb || true
  else
    echo "[INFO] LAMP ya instalado."
  fi
  a2enmod proxy proxy_http headers ssl rewrite >/dev/null 2>&1 || true
}

install_docker() {
  echo "[INFO] Verificando instalación Docker..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "[INFO] Instalando Docker..."
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
  else
    echo "[INFO] Docker ya instalado."
  fi
}

clone_repo() {
  echo "[INFO] Clonando/actualizando repositorio en ${DEST_DIR}..."
  if [[ -d "${DEST_DIR}/.git" ]]; then
    git -C "${DEST_DIR}" fetch --all --prune
    git -C "${DEST_DIR}" pull --ff-only || true
  else
    mkdir -p "${DEST_DIR}"
    git clone "${REPO_URL}" "${DEST_DIR}" || { echo "[ERROR] No se pudo clonar el repo"; exit 1; }
  fi
  chown -R www-data:www-data "${DEST_DIR}" || true
}

ensure_env() {
  if [[ ! -f "${DEST_DIR}/.env" ]]; then
    echo "[INFO] Creando .env base..."
    cat > "${DEST_DIR}/.env" <<ENV
GENERIC_TIMEZONE=Europe/Madrid
N8N_HOST=${DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=http
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
DB_POSTGRESDB_SCHEMA=public
# N8N_BASIC_AUTH_ACTIVE=true
# N8N_BASIC_AUTH_USER=admin
# N8N_BASIC_AUTH_PASSWORD=cambia
ENV
  fi
}

create_apache_vhost() {
  echo "[INFO] Configurando VirtualHost Apache..."
  local proto="http"
  $ENABLE_SSL && proto="https"
  cat > "$APACHE_CONF" <<VHOST
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${DEST_DIR}

    <Directory ${DEST_DIR}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Redirigir todo al contenedor n8n (puerto interno 5678)
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:5678/
    ProxyPassReverse / http://127.0.0.1:5678/

    # Encabezados útiles
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-Content-Type-Options nosniff
    Header always set Referrer-Policy strict-origin-when-cross-origin

    ErrorLog ${APACHE_LOG_DIR}/n8n-error.log
    CustomLog ${APACHE_LOG_DIR}/n8n-access.log combined
</VirtualHost>
VHOST
  a2dissite 000-default.conf >/dev/null 2>&1 || true
  a2ensite n8n.conf >/dev/null 2>&1
  systemctl reload apache2 || systemctl restart apache2
}

setup_ssl() {
  if $ENABLE_SSL; then
    echo "[INFO] Configurando SSL con Certbot..."
    if ! command -v certbot >/dev/null 2>&1; then
      apt-get install -y certbot python3-certbot-apache
    fi
    certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || {
      echo "[WARN] Falló emisión de certificado. Continuando sin SSL.";
    }
  fi
}

create_systemd_service() {
  echo "[INFO] Creando servicio systemd para n8n..."
  local service_path="/etc/systemd/system/${SYSTEMD_SERVICE}"
  cat > "$service_path" <<SERVICE
[Unit]
Description=n8n Docker Compose Service
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${DEST_DIR}
ExecStart=/usr/bin/${COMPOSE_CMD} up -d
ExecStop=/usr/bin/${COMPOSE_CMD} down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "${SYSTEMD_SERVICE}"
}

start_stack() {
  echo "[INFO] Levantando stack Docker n8n..."
  (cd "${DEST_DIR}" && ${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d)
}

summary() {
  echo "\n====================================="
  echo " Despliegue completado"
  echo " Dominio: http${ENABLE_SSL:+s}://${DOMAIN}/"
  echo " Directorio: ${DEST_DIR}"
  echo " Servicio systemd: ${SYSTEMD_SERVICE} (systemctl status ${SYSTEMD_SERVICE})"
  echo " Para ver logs n8n: docker compose -f ${DEST_DIR}/docker-compose.yml logs -f n8n"
  echo "=====================================\n"
}

main() {
  parse_args "$@"
  check_root
  update_system
  install_lamp
  install_docker
  clone_repo
  ensure_env
  create_apache_vhost
  setup_ssl
  create_systemd_service
  start_stack
  summary
}

main "$@"
