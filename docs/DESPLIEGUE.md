# Poner el servidor de Rescate en internet

La app de la tienda necesita que el backend esté en un servidor **siempre encendido y con HTTPS**.
Esta guía cubre las dos formas más simples. Los precios y límites son de octubre de 2026;
verifícalos antes de contratar.

## Qué opción elegir

| | Render gratis | Render de pago | VPS propio con Docker |
|---|---|---|---|
| Costo | 0 | ≈ 13–14 USD/mes (web 7 + base de datos ≈ 6–7) | según el proveedor |
| Siempre encendido | **No**: se duerme a los 15 min y tarda ~1 min en despertar | Sí | Sí |
| Base de datos | **Se borra a los 30 días** | Permanente | Permanente (tú haces copias) |
| Fotos de los packs | Se pierden al reiniciar | Necesitas un disco persistente | Se conservan en un volumen |
| Trabajo para ti | Mínimo | Bajo | Medio (actualizas y respaldas tú) |
| Sirve para | Una prueba de un día | Producción simple | Producción con el menor costo |

Para la prueba cerrada de Google (14 días con 12 testers) y para producción necesitas **una de
las dos últimas**. Un servidor que se duerme hace que el login falle la primera vez de cada rato.

> Sugerencia: usa un subdominio de tu dominio, por ejemplo `rescate-api.vectoraec.app`, para el
> servidor. Así la URL se ve profesional y no depende del hosting.

## Antes de desplegar (sea cual sea la opción)

Variables de entorno del backend (en `backend/.env`; ver `backend/.env.example`):

- `SECRET_KEY`: nueva, de 32+ caracteres. Genérala con
  `python -c "import secrets; print(secrets.token_urlsafe(48))"`.
- `COMPANY_NAME` y `SUPPORT_EMAIL`: aparecen en la política de privacidad.
- `RESEND_API_KEY` y `FROM_EMAIL`: correo de recuperación de contraseña (dominio verificado en
  Resend, llave nueva con permiso solo de envío).
- Notificaciones push: sube `firebase-service-account.json` a `backend/`, o pega su contenido en
  `FIREBASE_CREDENTIALS_JSON` si el hosting no te deja subir archivos.
- **No** pongas `DEV_PRINT_EMAILS` ni `CORS_ORIGINS` (la app móvil no los necesita).

## Opción A: VPS con Docker (todo incluido: API + PostgreSQL + HTTPS)

1. Contrata un servidor Linux (Ubuntu) con 1 GB de RAM o más e instala Docker:
   `curl -fsSL https://get.docker.com | sh`
2. En el DNS de tu dominio crea un registro **A** (`rescate-api` → la IP del servidor).
3. Descarga el proyecto y prepara los archivos de configuración:
   ```bash
   git clone https://github.com/HectorU-cloud/rescate-app.git
   cd rescate-app/deploy
   cp .env.example .env                     # completa DOMAIN y DB_PASSWORD
   cp ../backend/.env.example ../backend/.env   # completa SECRET_KEY, etc. (DATABASE_URL se ignora)
   ```
4. Levanta todo y crea las categorías (sin datos demo):
   ```bash
   docker compose up -d --build
   docker compose exec app python seed.py --solo-categorias
   ```
5. Comprueba que abra, **sin candado de advertencia**: `https://TU-DOMINIO/api/health`
   y `https://TU-DOMINIO/privacy`.
6. Compila la app apuntando a esa dirección (ver `docs/PUBLICAR_ANDROID.md`):
   `flutter build appbundle --release --dart-define=API_BASE_URL=https://TU-DOMINIO`

**Actualizar** después de cambios: `git pull && docker compose up -d --build`.

**Copias de seguridad** (hazlas desde el primer día; si el servidor se pierde, se pierde todo):
```bash
docker compose exec -T db pg_dump -U rescate rescate > respaldo-$(date +%F).sql
docker run --rm -v deploy_uploads:/data -v "$PWD":/out alpine tar czf /out/fotos-$(date +%F).tgz -C /data .
```
Prográmalas con `cron` y guarda los archivos **fuera** del servidor.

## Opción B: Render (sin administrar servidor)

1. Crea un **Web Service** desde tu repositorio de GitHub: entorno **Docker**, *Root Directory*
   `backend`. Render usa el `Dockerfile` y le pasa el puerto solo.
2. Crea una base **PostgreSQL de pago** en la misma región y copia su *Internal Database URL* en la
   variable `DATABASE_URL` del servicio.
3. Agrega las variables de la sección anterior.
4. Cuando termine de desplegar, abre la *Shell* del servicio y ejecuta
   `python seed.py --solo-categorias`.
5. Dominio propio: *Settings → Custom Domains* y el registro DNS que te indique.
6. **Fotos:** sin un disco persistente se pierden en cada reinicio. Si añades un disco, móntalo en
   `/data/uploads` y comprueba que puedes subir una foto (el contenedor corre sin privilegios y, si
   el disco no le deja escribir, la app responderá "No pudimos guardar la foto"). Mientras tanto,
   los packs sin foto muestran su ícono.

## Probar en tu computadora o red local

El `docker-compose.yml` **no** expone la API directamente: solo Caddy (HTTPS) es público, para que
nadie pueda saltarse el cifrado entrando por `http://IP:8000`. Para probar con el emulador o un
teléfono en tu red, agrega el archivo de pruebas, que sí abre el puerto 8000:

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
```

**Nunca** lo uses en el servidor de producción.

## Después de actualizar el código con una base de datos que ya tiene datos

Cuando una versión agrega columnas nuevas, ejecuta una vez:

```bash
docker compose exec app python migrate.py
```

(Es seguro repetirlo.) La versión que agregó el inicio de sesión con Google y el cierre de sesiones
necesita esto. Las sesiones que ya estaban abiertas siguen funcionando.

## Lista de comprobación después de desplegar

- [ ] `https://TU-DOMINIO/api/health` responde `healthy`.
- [ ] `/privacy`, `/terms` y `/account-deletion` abren y muestran tu nombre y correo.
- [ ] Creas una cuenta, pides recuperar la contraseña y **llega el código** (revisa spam en Gmail
      y Hotmail).
- [ ] Subes la foto de un pack, reinicias el servicio y la foto sigue ahí.
- [ ] Llega una notificación push al reservar.
- [ ] Reinicias el servidor y todo vuelve solo.

## Cosas que debes saber

- **Base nueva:** las tablas se crean solas al arrancar. `python migrate.py` solo hace falta si
  actualizas una base **antigua**.
- **Límites de intentos** (login: 5 fallos por cuenta y 30 por IP cada 15 min; códigos de
  recuperación: 10 por IP por hora) viven en la memoria de cada proceso. Con un solo proceso, que
  es lo configurado, funcionan exacto; si algún día usas varios, conviene moverlos a Redis.
- **Cambiar la contraseña, o vincular una cuenta existente con Google, cierra todas las sesiones abiertas** de esa cuenta.
- El `Dockerfile` y el `docker-compose.yml` **no se pudieron probar** al prepararlos (no había
  Docker disponible). Si algo falla al levantarlos, revisa `docker compose logs app`.
