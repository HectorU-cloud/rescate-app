# Publicar Rescate en Google Play (y luego iOS)

Guía en orden. Lo marcado con ⚠️ es lo que más rechazos causa.

## 0. Antes de empezar: qué tipo de cuenta de Google Play

- **Cuenta personal** (25 USD, pago único): si se creó después del 13/11/2023, Google exige una
  **prueba cerrada con al menos 12 testers durante 14 días seguidos** antes de poder pasar a
  producción. Cuenta ≥ 3 semanas desde que subes la primera versión hasta publicar.
- **Cuenta de organización**: no tiene esa regla, pero requiere una empresa registrada (y número
  D-U-N-S).

Ve reclutando desde ya a 12+ personas con teléfono Android y cuenta de Google (familia, amigos,
compañeros, y los primeros negocios). Deben **mantenerse inscritas los 14 días completos**.

## 1. Servidor en producción

La app no sirve en la tienda si el backend solo está en tu PC.

- Aloja el backend con **HTTPS** (Android bloquea `http://` en versiones de lanzamiento). Guía con
  las opciones y los pasos: [`DESPLIEGUE.md`](DESPLIEGUE.md).
- Variables de entorno en el servidor:
  - `DATABASE_URL` · `SECRET_KEY` (≥ 32 caracteres, nueva, no la del repo)
  - `SUPPORT_EMAIL` y `COMPANY_NAME` → aparecen en la política de privacidad y términos
  - `RESEND_API_KEY` y `FROM_EMAIL` → correo para recuperar contraseña. Verifica el dominio en
    Resend, usa una llave nueva con permiso solo de envío y prueba que el código llegue a Gmail y
    Hotmail (revisa spam) **antes** de publicar.
  - `firebase-service-account.json` en `backend/`
- Las fotos se guardan en `backend/uploads/`: usa un **volumen persistente** o se perderán al
  reiniciar.
- Comprueba que estas URLs abren sin iniciar sesión (las pide Google):
  - `https://TU-SERVIDOR/privacy`
  - `https://TU-SERVIDOR/terms`
  - `https://TU-SERVIDOR/account-deletion`
- Ya están hechos: CORS cerrado por defecto, `/api/health` sin detalles internos y límite de
  intentos de login.

## 2. ⚠️ Cambiar el identificador de la app (permanente)

Hoy es `com.example.mobile`. **Google Play rechaza `com.example.*`** y, una vez subida la primera
versión, **ya no se puede cambiar**. Elige uno propio, por ejemplo `ec.tudominio.rescate`.

Hazlo todo junto, o el build falla:

1. En Firebase Console: agrega una app Android nueva con el identificador nuevo y descarga su
   `google-services.json` → reemplaza `mobile/android/app/google-services.json`.
2. En `mobile/android/app/build.gradle.kts` cambia `namespace` y `applicationId`.
3. Mueve `android/app/src/main/kotlin/com/example/mobile/MainActivity.kt` a la carpeta del
   nuevo paquete y cambia su primera línea `package ...`.
4. `flutter clean` y prueba que compile y que lleguen notificaciones.

## 3. Icono y nombre

El nombre visible ya es **Rescate**. El icono sigue siendo el de Flutter: reemplázalo
(paquete `flutter_launcher_icons`). Google también pide un icono de 512×512 para la ficha.

## 4. ⚠️ Llave de firma (guárdala bien)

Google no acepta apps firmadas con la llave de debug.

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Mueve `upload-keystore.jks` a `mobile/android/` y crea `mobile/android/key.properties`:

```
storePassword=TU_CLAVE
keyPassword=TU_CLAVE
keyAlias=upload
storeFile=../upload-keystore.jks
```

Ambos archivos ya están en el `.gitignore`. **Haz una copia de seguridad fuera del repo**
(si la pierdes, subir actualizaciones se vuelve un trámite con Google). Activa **Play App
Signing** cuando la consola te lo ofrezca.

## 5. Generar la versión de lanzamiento

```bash
cd mobile
flutter build appbundle --release --dart-define=API_BASE_URL=https://TU-SERVIDOR
```

⚠️ Sin `--dart-define` la app apuntaría al emulador (`10.0.2.2`) y no funcionaría.
El archivo queda en `build/app/outputs/bundle/release/app-release.aab`.
Cada vez que subas una versión, aumenta el número tras el `+` en `version:` de `pubspec.yaml`
(`1.0.0+1` → `1.0.0+2`).

## 6. Ficha y formularios en Play Console

- **Ficha:** descripción, capturas de teléfono (mínimo 2), icono 512×512 y gráfico de 1024×500.
- **Política de privacidad:** `https://TU-SERVIDOR/privacy`
- **Eliminación de cuenta** (pide la URL y que exista en la app): `https://TU-SERVIDOR/account-deletion`
- **Acceso a la app:** Google revisa la app con sesión iniciada. Entrégale usuarios de prueba:
  uno **cliente** y uno **negocio** (puedes crearlos con `python seed.py`).
- **Anuncios:** no. **Público objetivo:** adultos (18+). **Clasificación de contenido:** responde
  el cuestionario (app de comida, sin contenido sensible).
- **Permisos:** ubicación en primer plano (packs cercanos) y cámara (escanear QR).
- **Seguridad de los datos** (según lo que hace la app hoy; revísalo si cambia algo):

| Dato | ¿Recopilado? | Detalle |
|---|---|---|
| Nombre y correo | Sí | Cuenta. Se muestra al negocio donde reservas. El correo se comparte con Resend solo para enviar el código de recuperación. |
| Ubicación | No | Se usa solo en el teléfono, no sale del dispositivo. |
| Fotos | Sí (negocios) | Las fotos de los packs. |
| Identificador de dispositivo | Sí | Token de notificaciones (Firebase). |
| Historial de reservas | Sí | Actividad dentro de la app. |
| Pagos / tarjetas | No | Hoy solo efectivo al retirar. |

Cifrado en tránsito: **sí** (HTTPS). Los usuarios pueden pedir eliminar sus datos: **sí**.

## 7. Camino a producción

1. **Prueba interna** (hasta 100 testers, sin esperas) para ver que todo funcione.
2. **Prueba cerrada** con 12+ testers inscritos 14 días seguidos (cuenta personal nueva).
3. Pide **acceso a producción** y responde el cuestionario con ejemplos reales de lo que
   probaron y arreglaste.
4. Revisión de Google: normalmente de 1 a 7 días.

## 8. Después, iOS

Lo que cambia respecto a Android:

- **Apple Developer Program:** 99 USD al año.
- **Un Mac con Xcode** (o un servicio de compilación en la nube como Codemagic) para generar la
  app.
- **Identificador (Bundle ID)** propio y una app iOS en Firebase (`GoogleService-Info.plist`).
- ⚠️ **Notificaciones push en iOS:** necesitas subir una llave APNs a Firebase; sin ella no llegan.
- **Textos de permisos** en `ios/Runner/Info.plist`: ya están ubicación, cámara y fotos.
- **Privacidad de la App Store** ("etiquetas de privacidad"): se llena con la misma tabla de arriba.
- **Eliminar cuenta dentro de la app:** Apple también lo exige; ya está hecho.
- **Cuenta de prueba** para los revisores de Apple y TestFlight para las pruebas.
- Apple **no** exige "Iniciar sesión con Apple" mientras no ofrezcas login con Google o Facebook.
