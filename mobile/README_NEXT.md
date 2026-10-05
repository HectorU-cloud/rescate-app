# Amora / Rescate - siguiente etapa

Este paquete contiene el punto de continuación del proyecto.

## Lo que ya viene preparado

- Backend FastAPI + PostgreSQL.
- CRUD base de usuarios, negocios, categorías y Food Packs.
- API de reservas:
  - `GET /api/reservations?user_id=1`
  - `GET /api/reservations/{id}`
  - `POST /api/reservations`
  - `PATCH /api/reservations/{id}/cancel`
- Al reservar se descuenta la cantidad disponible del Food Pack.
- Cuando llega a cero, el pack pasa a `sold_out`.
- Al cancelar una reserva, las unidades vuelven al pack.
- Cliente HTTP Flutter preparado en `lib/services/api_service.dart`.
- Dependencia `http` agregada.
- `FoodPack.fromJson()` preparado para consumir la API.

## Antes de continuar

1. Mantén tu `.env` local del backend. No se incluye en este paquete por seguridad.
2. En `mobile/lib/services/api_service.dart`, `10.0.2.2` funciona para el Android Emulator. Para un teléfono físico cambia la URL por la IP LAN de tu PC.
3. Ejecuta `flutter pub get` dentro de `mobile`.
4. Arranca PostgreSQL y luego:
   `uvicorn main:app --reload`
5. Prueba `http://127.0.0.1:8000/docs`.

## Lo siguiente que haremos manualmente

- Login/registro real desde Flutter.
- Persistencia de sesión.
- Cargar Food Packs reales en Inicio.
- Crear reservas reales desde la pantalla de detalle.
- Mostrar reservas reales en Mis Rescates.
- Después: mapa, negocio, panel del comercio, imágenes y retoques UX/UI.
