"""Paginas legales publicas: privacidad, terminos y eliminacion de cuenta.

Google Play y la App Store piden una URL publica para cada una. Se sirven
desde el propio backend:

    https://TU-SERVIDOR/privacy
    https://TU-SERVIDOR/terms
    https://TU-SERVIDOR/account-deletion

IMPORTANTE: son un BORRADOR basado en lo que hace la app hoy. No es
asesoria legal: hazlas revisar por un abogado antes de publicar y vuelve a
revisarlas cada vez que la app recolecte datos nuevos (pagos, analiticas...).

Datos del titular, por .env:
    COMPANY_NAME   nombre de la persona o empresa responsable
    SUPPORT_EMAIL  correo de contacto (obligatorio para publicar)
"""
import os
from html import escape

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["Legal"], include_in_schema=False)

LAST_UPDATED = "5 de octubre de 2026"


def _company() -> str:
    return escape(os.getenv("COMPANY_NAME", "").strip() or "[configura COMPANY_NAME]")


def _email() -> str:
    email = escape(os.getenv("SUPPORT_EMAIL", "").strip())
    if not email:
        return "[configura SUPPORT_EMAIL]"
    return f'<a href="mailto:{email}">{email}</a>'


def _page(title: str, body: str) -> HTMLResponse:
    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)} · Rescate</title>
<style>
  body {{ font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
         line-height: 1.6; color: #1f2937; margin: 0; background: #f8fafc; }}
  main {{ max-width: 760px; margin: 0 auto; padding: 24px 20px 60px;
         background: #fff; min-height: 100vh; }}
  h1 {{ color: #0f766e; margin-bottom: 4px; }}
  h2 {{ margin-top: 32px; font-size: 1.15rem; }}
  .updated {{ color: #6b7280; margin-top: 0; }}
  a {{ color: #0f766e; }}
  li {{ margin-bottom: 6px; }}
</style>
</head>
<body><main>
<h1>{escape(title)}</h1>
<p class="updated">Última actualización: {LAST_UPDATED}</p>
{body}
</main></body></html>"""
    return HTMLResponse(html)


@router.get("/privacy", response_class=HTMLResponse)
def privacy_policy():
    return _page(
        "Política de privacidad",
        f"""
<p>Rescate es una aplicación que permite reservar a precio reducido packs de
comida que los negocios no alcanzaron a vender. Esta política explica qué datos
personales tratamos, para qué y qué derechos tienes. Aplica la Ley Orgánica de
Protección de Datos Personales de Ecuador.</p>

<h2>1. Responsable del tratamiento</h2>
<p>{_company()}. Contacto para temas de privacidad: {_email()}.</p>

<h2>2. Qué datos recopilamos</h2>
<ul>
  <li><strong>Cuenta:</strong> nombre, correo electrónico y contraseña
      (la guardamos cifrada; nosotros no podemos verla).</li>
  <li><strong>Reservas:</strong> qué pack reservaste, cantidad, monto, método
      de pago, estado (reservado, retirado, cancelado o no retirado) y fechas.</li>
  <li><strong>Si eres un negocio:</strong> nombre del local, descripción,
      dirección, ciudad, teléfono, ubicación del local y las fotos de tus packs.</li>
  <li><strong>Notificaciones:</strong> un identificador de tu dispositivo para
      enviarte avisos sobre tus reservas.</li>
  <li><strong>Ubicación del dispositivo:</strong> si lo permites, la app usa tu
      ubicación para mostrarte los packs más cercanos. Se usa en tu teléfono y
      <strong>no se envía ni se guarda en nuestros servidores</strong>.</li>
  <li><strong>Cámara:</strong> solo para escanear códigos QR de retiro. No
      guardamos fotos ni videos.</li>
  <li><strong>Fotos de la galería:</strong> solo las que eliges para un pack
      (negocios). Eliminamos los metadatos de la imagen, incluida su ubicación.</li>
</ul>
<p>Hoy el pago es en efectivo al retirar, por eso <strong>no recopilamos datos
de tarjetas</strong>.</p>

<h2>3. Para qué usamos tus datos</h2>
<ul>
  <li>Crear y administrar tu cuenta.</li>
  <li>Gestionar reservas, retiros y cancelaciones.</li>
  <li>Enviarte notificaciones sobre tus reservas y el código para recuperar tu
      contraseña.</li>
  <li>Mostrar a los negocios sus reservas y estadísticas.</li>
  <li>Prevenir abusos, por ejemplo limitando nuevas reservas a quien deja varias
      sin retirar.</li>
  <li>Cumplir obligaciones legales y contables.</li>
</ul>

<h2>4. Con quién compartimos tus datos</h2>
<ul>
  <li><strong>El negocio donde reservas</strong> ve tu nombre, el código y los
      datos de tu reserva. Tú ves el nombre, dirección y teléfono del negocio.</li>
  <li><strong>Google Firebase</strong> procesa los identificadores de
      dispositivo para entregar las notificaciones.</li>
  <li><strong>Resend</strong>, servicio de envío de correo, procesa tu correo
      electrónico y el código de verificación cuando recuperas tu
      contraseña.</li>
  <li><strong>OpenStreetMap:</strong> al ver el mapa, tu dispositivo descarga
      imágenes del mapa desde sus servidores, que reciben tu dirección IP.</li>
  <li><strong>Proveedor de alojamiento del servidor</strong>, que almacena la
      información por encargo nuestro.</li>
</ul>
<p>No vendemos tus datos personales ni los usamos para publicidad de terceros.</p>

<h2>5. Cuánto tiempo los conservamos</h2>
<p>Mientras tengas tu cuenta. Si la eliminas, borramos tu nombre, correo,
contraseña e identificadores de dispositivo. Los registros de reservas pasadas
se conservan <strong>sin datos personales</strong>, porque los negocios los
necesitan para su contabilidad.</p>

<h2>6. Tus derechos</h2>
<p>Puedes solicitar acceso, rectificación, actualización, eliminación,
oposición, limitación del tratamiento y portabilidad de tus datos.</p>
<ul>
  <li><strong>Eliminar tu cuenta:</strong> desde la app, en Perfil → Eliminar
      cuenta. También puedes seguir los pasos en
      <a href="/account-deletion">esta página</a>.</li>
  <li><strong>Otros derechos:</strong> escríbenos a {_email()}.</li>
</ul>
<p>Si consideras que no atendimos tu solicitud, puedes presentar un reclamo
ante la autoridad de protección de datos personales de Ecuador.</p>

<h2>7. Seguridad</h2>
<p>Protegemos la información con conexiones cifradas y almacenamos las
contraseñas de forma cifrada. Ningún sistema es 100 % seguro, pero trabajamos
para reducir los riesgos.</p>

<h2>8. Menores de edad</h2>
<p>Rescate no está dirigida a menores de 18 años y no recopilamos
intencionalmente sus datos.</p>

<h2>9. Cambios a esta política</h2>
<p>Si hacemos cambios importantes, te avisaremos en la app. La fecha de arriba
indica la última actualización.</p>

<h2>10. Contacto</h2>
<p>{_company()} · {_email()}</p>
""",
    )


@router.get("/terms", response_class=HTMLResponse)
def terms_of_service():
    return _page(
        "Términos y condiciones",
        f"""
<p>Al crear una cuenta o usar Rescate aceptas estos términos. Léelos con
calma; si no estás de acuerdo, no uses la app.</p>

<h2>1. Qué es Rescate</h2>
<p>Rescate conecta a negocios con clientes para reservar packs de comida
excedente a precio reducido. Rescate es solo un intermediario: no prepara,
almacena ni entrega la comida, que es responsabilidad del negocio.</p>

<h2>2. Tu cuenta</h2>
<ul>
  <li>Debes tener al menos 18 años.</li>
  <li>Debes dar datos verdaderos y mantener segura tu contraseña.</li>
  <li>Eres responsable de lo que ocurra desde tu cuenta.</li>
</ul>

<h2>3. Reservas y retiro</h2>
<ul>
  <li>Reservas un pack y lo retiras en el local, dentro del horario indicado,
      mostrando tu código o QR.</li>
  <li>El pago se hace en efectivo al retirar, salvo que la app indique otro
      método.</li>
  <li>En los packs sorpresa el contenido exacto puede variar.</li>
</ul>

<h2>4. Cancelaciones y reservas no retiradas</h2>
<ul>
  <li>Puedes cancelar tu reserva desde la app antes de que termine el horario.</li>
  <li>Si no retiras tu reserva dentro del horario (más un breve margen), se
      marca como <strong>"No retirado"</strong>: el pack no se repone ni se
      devuelve.</li>
  <li>Si acumulas varias reservas no retiradas en un período corto, podemos
      bloquear temporalmente nuevas reservas.</li>
</ul>

<h2>5. Si eres un negocio</h2>
<ul>
  <li>Eres responsable de la calidad, higiene, conservación, etiquetado y
      cumplimiento de las normas sanitarias de lo que entregas.</li>
  <li>Debes indicar con exactitud precio, cantidad, horario y contenido, y
      respetar las reservas confirmadas.</li>
  <li>Rescate puede cobrar una comisión por servicio, que se muestra en la app.</li>
</ul>

<h2>6. Alérgenos y seguridad alimentaria</h2>
<p>Rescate no verifica los ingredientes ni los alérgenos de los packs. Si
tienes alergias o restricciones alimentarias, consúltalas directamente con el
negocio antes de retirar.</p>

<h2>7. Conductas no permitidas</h2>
<ul>
  <li>Dar información falsa, suplantar a otra persona o crear cuentas para
      abusar del sistema.</li>
  <li>Publicar contenido ilegal, ofensivo o que no te pertenezca.</li>
  <li>Intentar vulnerar la seguridad de la app o interferir con su uso.</li>
</ul>

<h2>8. Contenido que subes</h2>
<p>Si subes fotos u otros contenidos, declaras que tienes derecho a hacerlo y
nos autorizas a mostrarlos en la app con el único fin de operar el servicio.</p>

<h2>9. Suspensión de cuentas</h2>
<p>Podemos suspender o cerrar cuentas que incumplan estos términos. Tú puedes
eliminar tu cuenta cuando quieras desde la app.</p>

<h2>10. Limitación de responsabilidad</h2>
<p>En la medida que permita la ley, Rescate no responde por la calidad o
condición de la comida, ni por daños derivados de la relación entre cliente y
negocio. Esto no limita derechos que la ley te reconozca como consumidor.</p>

<h2>11. Cambios y ley aplicable</h2>
<p>Podemos actualizar estos términos y te avisaremos de los cambios
importantes. Se rigen por las leyes de Ecuador.</p>

<h2>12. Contacto</h2>
<p>{_company()} · {_email()}</p>
""",
    )


@router.get("/account-deletion", response_class=HTMLResponse)
def account_deletion():
    return _page(
        "Eliminar tu cuenta de Rescate",
        f"""
<p>Puedes eliminar tu cuenta y tus datos personales en cualquier momento.</p>

<h2>Opción 1: desde la app</h2>
<ol>
  <li>Abre Rescate e inicia sesión.</li>
  <li>Ve a <strong>Perfil</strong>.</li>
  <li>Toca <strong>Eliminar cuenta</strong> y confirma con tu contraseña.</li>
</ol>
<p>Antes debes retirar o cancelar tus reservas pendientes. Si eres un negocio,
debes haber entregado las reservas de tus clientes.</p>

<h2>Opción 2: por correo</h2>
<p>Si no puedes entrar a la app, escríbenos a {_email()} desde el correo con el
que te registraste, con el asunto "Eliminar mi cuenta". Atenderemos tu
solicitud en un máximo de 15 días.</p>

<h2>Qué se elimina</h2>
<ul>
  <li>Tu nombre, correo y contraseña.</li>
  <li>Los identificadores de tu dispositivo para notificaciones.</li>
  <li>Si eres un negocio: tu teléfono, dirección, ubicación, descripción y las
      fotos de tus packs; tus packs dejan de mostrarse.</li>
</ul>

<h2>Qué se conserva</h2>
<p>El historial de reservas pasadas se conserva <strong>sin ningún dato
personal</strong>, porque los negocios lo necesitan para su contabilidad.</p>

<p>Más información en nuestra <a href="/privacy">política de privacidad</a>.</p>
""",
    )
