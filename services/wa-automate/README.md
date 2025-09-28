# open-wa/wa-automate-nodejs - Integración Docker

Este servicio te permite usar WhatsApp vía API REST y recibir eventos por webhook usando open-wa/wa-automate-nodejs.

## 1. Cómo levantar el servicio

Agrega este servicio a tu `docker-compose.yml`:

```yaml
wa-automate:
  build: ./services/wa-automate
  ports:
    - "3000:3000"   # Interfaz web
    - "3001:3001"   # API REST
  volumes:
    - ./services/wa-automate/config.json:/usr/src/app/config.json
  restart: unless-stopped
```

## 2. Configuración básica

Edita `config.json` para:
- Cambiar el puerto de la API (`apiPort`)
- Configurar el webhook (`webhook.url`)
- Personalizar otros parámetros (ver docs oficiales)

Ejemplo:
```json
{
  "host": "0.0.0.0",
  "port": 3000,
  "apiHost": "0.0.0.0",
  "apiPort": 3001,
  "webhook": {
    "enabled": true,
    "url": "http://n8n:5678/webhook/wa-automate"
  }
}
```

## 3. Añadir teléfono (login)

Al iniciar el contenedor por primera vez, accede a `http://localhost:3000` para escanear el QR con tu móvil y vincular el número.

## 4. Consumir la API REST

La API está disponible en `http://localhost:3001`.

### Ejemplo: Enviar mensaje

```bash
curl -X POST http://localhost:3001/sendText -H "Content-Type: application/json" -d '{"to":"346XXXXXXXX","content":"Hola desde API!"}'
```

Más endpoints en la documentación oficial: https://openwa.dev/docs/api

## 5. Configurar Webhook

El webhook enviará eventos (mensajes recibidos, estado, etc.) a la URL configurada en `config.json`.

Ejemplo de payload recibido:
```json
{
  "event": "onMessage",
  "data": {
    "from": "346XXXXXXXX",
    "body": "Hola!"
  }
}
```

## 6. Recursos útiles
- [Documentación oficial](https://openwa.dev/docs/)
- [Ejemplos de API](https://openwa.dev/docs/api)
- [Webhooks](https://openwa.dev/docs/webhooks)

## 7. Notas
- El contenedor requiere que escanees el QR en cada nuevo volumen.
- Puedes proteger la API con autenticación (ver docs open-wa).
- Para producción, usa HTTPS y restringe acceso a la API.
