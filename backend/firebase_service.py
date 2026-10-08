import base64
import json
import logging
import os

import firebase_admin
from firebase_admin import auth, credentials, messaging
from fastapi import HTTPException


logger = logging.getLogger("rescate.firebase")

SERVICE_ACCOUNT_PATH = os.path.join(
    os.path.dirname(__file__),
    "firebase-service-account.json",
)

_firebase_app = None


def _load_credentials():
    """Credenciales de Firebase.

    En un hosting donde no se puede subir el archivo, pega su contenido en la
    variable FIREBASE_CREDENTIALS_JSON (el JSON tal cual, o codificado en
    base64). Si no existe, se usa el archivo firebase-service-account.json.
    """
    raw = os.getenv("FIREBASE_CREDENTIALS_JSON", "").strip()

    if raw:
        if not raw.startswith("{"):
            raw = base64.b64decode(raw).decode("utf-8")

        return credentials.Certificate(json.loads(raw))

    if os.path.exists(SERVICE_ACCOUNT_PATH):
        return credentials.Certificate(SERVICE_ACCOUNT_PATH)

    raise HTTPException(
        status_code=500,
        detail="Faltan las credenciales de Firebase (archivo o FIREBASE_CREDENTIALS_JSON)",
    )


def _get_app():
    global _firebase_app

    if _firebase_app is None:
        _firebase_app = firebase_admin.initialize_app(_load_credentials())

    return _firebase_app



def verify_id_token(id_token: str) -> dict:
    """Verifica un Firebase ID token y devuelve sus datos confiables."""
    _get_app()  # si faltan credenciales, el error real (500) sube tal cual

    try:
        return auth.verify_id_token(id_token)

    except (
        auth.InvalidIdTokenError,
        auth.ExpiredIdTokenError,
        auth.RevokedIdTokenError,
        ValueError,
    ) as error:
        logger.info("ID token rechazado: %s", error)
        raise HTTPException(
            status_code=401,
            detail="No se pudo validar la cuenta de Google.",
        )

    except Exception:
        # Sin red, certificados de Google no disponibles, etc.
        logger.exception("Fallo inesperado al validar el ID token")
        raise HTTPException(
            status_code=503,
            detail="No pudimos validar tu cuenta de Google ahora. Inténtalo más tarde.",
        )


def delete_firebase_user(uid: str) -> None:
    """Borra al usuario de Firebase Authentication (correo, nombre, foto).

    Si ya no existe se considera hecho. Cualquier otro fallo detiene la
    eliminacion de la cuenta para no dejar datos personales olvidados.
    """
    _get_app()

    try:
        auth.delete_user(uid)

    except auth.UserNotFoundError:
        return

    except Exception:
        logger.exception("No se pudo borrar el usuario %s de Firebase", uid)
        raise HTTPException(
            status_code=503,
            detail="No pudimos eliminar tu cuenta de Google ahora. Inténtalo más tarde.",
        )


def send_push(
    token: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> bool:
    """Envía una notificación push a un solo dispositivo."""
    try:
        _get_app()

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            token=token,
        )

        response = messaging.send(message)
        print(f"✅ Push enviado: {response}")
        return True

    except Exception as error:
        print(f"❌ Error enviando push a {token[:20]}...: {error}")
        return False


def send_push_to_user(
    db,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
) -> int:
    """Envía push a TODOS los dispositivos de un usuario."""
    from models.device_token import DeviceToken

    tokens = (
        db.query(DeviceToken)
        .filter(DeviceToken.user_id == user_id)
        .all()
    )

    sent = 0

    for t in tokens:
        if send_push(t.token, title, body, data):
            sent += 1

    return sent