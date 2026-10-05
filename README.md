# Rescate 🥖

App móvil para **rescatar comida** en Ecuador: panaderías, cafeterías y restaurantes publican packs sorpresa con descuento al final del día, y los clientes los reservan y los retiran en el local. Menos desperdicio, comida más barata. (MVP)

## Cómo funciona

1. El **negocio** se registra, crea su local y publica packs (precio, cantidad, horario de retiro).
2. El **cliente** ve los packs en lista y mapa, reserva y recibe un código QR.
3. En el local, el negocio **escanea el QR** para validar el retiro.

## Qué incluye

- Registro e inicio de sesión (cliente / negocio) con JWT
- Lista y mapa de packs cercanos
- Reservas, cancelación y "Mis rescates"
- Panel del negocio: packs, reservas recibidas, estadísticas y escáner de QR
- Notificaciones push (Firebase)
- Buscador y filtros por categoría
- Fotos de los packs (el negocio las sube desde su galería)
- Pago en efectivo al retirar (pago online: próximamente)

## Estructura

| Carpeta | Contenido |
|---|---|
| `backend/` | API en FastAPI + PostgreSQL |
| `mobile/` | App en Flutter |

## Puesta en marcha

### Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env            # y completa los valores
```

En `.env` define:

- `DATABASE_URL`: conexión a PostgreSQL.
- `SECRET_KEY`: **obligatoria**, mínimo 32 caracteres. Genérala con:
  `python -c "import secrets; print(secrets.token_urlsafe(48))"`
- `SEED_DEMO_PASSWORD` (opcional): contraseña de las cuentas demo.

Las fotos se guardan en `backend/uploads/` (no se sube al repo). En un servidor con disco temporal (Render, Railway, etc.) se pierden al reiniciar: monta un volumen persistente o migra a almacenamiento en la nube.

Para las notificaciones push, coloca `firebase-service-account.json` dentro de `backend/` (no se sube al repo).

```bash
python seed.py                  # datos demo (muestra la contraseña demo en consola)
uvicorn main:app --reload --host 0.0.0.0
```

Documentación interactiva: http://127.0.0.1:8000/docs

### App móvil

```bash
cd mobile
flutter pub get
# Emulador de Android (usa 10.0.2.2 por defecto):
flutter run
# Teléfono físico o servidor remoto:
flutter run --dart-define=API_BASE_URL=http://IP_DE_TU_PC:8000
```

Para notificaciones push, agrega tu `google-services.json` en `mobile/android/app/` (no se sube al repo).

## Cuentas demo

Después de correr `seed.py`:

- `panaderia.demo@rescate.ec` (negocio)
- `cafe.demo@rescate.ec` (negocio)

Contraseña: la que imprime `seed.py` (o `SEED_DEMO_PASSWORD`).

## Pendiente / ideas

- Fotos con cámara (hoy solo galería) y guardado de fotos en la nube
- Pago online con tarjeta
- Recuperar contraseña, términos y privacidad
- Calificaciones, alérgenos e ingredientes
- Tests automáticos del flujo reservar → retirar
