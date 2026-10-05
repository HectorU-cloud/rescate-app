import os

import firebase_admin
from firebase_admin import credentials, messaging
from fastapi import HTTPException


SERVICE_ACCOUNT_PATH = os.path.join(
    os.path.dirname(__file__),
    "firebase-service-account.json",
)

_firebase_app = None


def _get_app():
    global _firebase_app

    if _firebase_app is None:
        if not os.path.exists(SERVICE_ACCOUNT_PATH):
            raise HTTPException(
                status_code=500,
                detail="Archivo firebase-service-account.json no encontrado",
            )

        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        _firebase_app = firebase_admin.initialize_app(cred)

    return _firebase_app


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