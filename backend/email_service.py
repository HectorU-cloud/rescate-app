"""Envio de correos con Resend (https://resend.com).

Variables de entorno:
    RESEND_API_KEY   llave de Resend (de preferencia solo con permiso de envio)
    FROM_EMAIL       remitente, por ejemplo:  Rescate <rescate@vectoraec.app>
    DEV_PRINT_EMAILS poner 1 SOLO en desarrollo para ver en la consola los
                     correos que no se pueden enviar (por ejemplo, sin llave)

Se llama a la API REST de Resend directamente con httpx; no hace falta
instalar nada mas.
"""
import logging
import os

import httpx

logger = logging.getLogger("rescate.email")

RESEND_URL = "https://api.resend.com/emails"


def send_email(to: str, subject: str, html: str, text: str) -> bool:
    """Envia un correo. Devuelve True si Resend lo acepto.

    Nunca lanza excepciones: un fallo de correo no debe tumbar la API.
    """
    api_key = os.getenv("RESEND_API_KEY", "").strip()
    sender = os.getenv("FROM_EMAIL", "").strip()

    if not api_key or not sender:
        logger.warning(
            "Correo NO enviado: faltan RESEND_API_KEY o FROM_EMAIL en el .env"
        )
        if os.getenv("DEV_PRINT_EMAILS") == "1":
            print(f"\n--- CORREO (modo desarrollo) ---\nPara: {to}\n"
                  f"Asunto: {subject}\n{text}\n--------------------------------\n")
        return False

    try:
        response = httpx.post(
            RESEND_URL,
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "from": sender,
                "to": [to],
                "subject": subject,
                "html": html,
                "text": text,
            },
            timeout=10,
        )
    except httpx.HTTPError as error:
        logger.error("Resend no respondio: %s", error)
        return False

    if response.status_code >= 400:
        # El cuerpo explica la causa (dominio sin verificar, llave invalida...)
        logger.error("Resend rechazo el correo (%s): %s", response.status_code, response.text[:300])
        return False

    return True


def send_password_reset_code(to: str, name: str, code: str, minutes: int) -> bool:
    first_name = (name or "").split(" ")[0] or "hola"

    subject = f"Tu código de Rescate: {code}"

    text = (
        f"Hola {first_name},\n\n"
        f"Tu código para recuperar tu contraseña de Rescate es: {code}\n\n"
        f"Vence en {minutes} minutos. Si tú no lo pediste, ignora este mensaje: "
        "tu cuenta sigue segura.\n\n— Rescate"
    )

    html = f"""<!DOCTYPE html>
<html lang="es"><body style="margin:0;padding:24px;background:#f4f7f6;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">
<div style="max-width:420px;margin:0 auto;background:#ffffff;border-radius:16px;padding:28px;">
  <h2 style="margin:0 0 8px;color:#0f766e;">Rescate</h2>
  <p>Hola {first_name},</p>
  <p>Usa este código para recuperar tu contraseña:</p>
  <p style="font-size:34px;letter-spacing:8px;font-weight:bold;text-align:center;margin:24px 0;color:#0f766e;">{code}</p>
  <p style="color:#6b7280;font-size:14px;">Vence en {minutes} minutos. Si tú no lo pediste, ignora este mensaje: tu cuenta sigue segura.</p>
</div></body></html>"""

    return send_email(to, subject, html, text)
