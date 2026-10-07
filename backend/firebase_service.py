import base64
import json
import os

import firebase_admin
from firebase_admin import auth, credentials, messaging
from fastapi import HTTPException


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
    """Verifica un Firebase ID token y devuelve sus claims confiables."""
    try:
        _get_app()
        return auth.verify_id_token(id_token)
    except Exception as error:
        print(f"❌ Firebase ID token inválido: {error}")
        raise HTTPException(
            status_code=401,
            detail="No se pudo validar la cuenta de Google.",
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