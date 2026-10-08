import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from database import get_db
from models.business import Business
from models.device_token import DeviceToken
from models.food_pack import FoodPack
from models.password_reset import PasswordReset
from models.reservation import Reservation
from models.user import User
from email_service import send_password_reset_code
from firebase_service import delete_firebase_user, verify_id_token
from rate_limit import (
    client_ip,
    forgot_by_ip,
    google_fail_by_ip,
    login_by_account,
    login_by_ip,
)
from reservation_rules import expire_overdue_reservations
from routers.uploads import delete_pack_image_file
from schemas.auth import (
    RegisterRequest,
    LoginRequest,
    GoogleLoginRequest,
    AuthResponse,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    MessageResponse,
    ResetPasswordRequest,
)
from security import get_current_user, issue_token


router = APIRouter(
    prefix="/api/auth",
    tags=["Authentication"],
)


pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto",
)


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=201,
)
def register(
    data: RegisterRequest,
    db: Session = Depends(get_db),
):
    existing_user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="El correo ya está registrado",
        )

    if len(data.password) < 6:
        raise HTTPException(
            status_code=400,
            detail="La contraseña debe tener al menos 6 caracteres",
        )

    password_hash = pwd_context.hash(data.password)

    new_user = User(
        name=data.name,
        email=data.email,
        password_hash=password_hash,
        is_business=data.is_business,
        is_active=True,
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    access_token = issue_token(new_user)

    return AuthResponse(
        message="Usuario registrado correctamente",
        user_id=new_user.id,
        name=new_user.name,
        email=new_user.email,
        is_business=new_user.is_business,
        access_token=access_token,
    )


@router.post(
    "/login",
    response_model=AuthResponse,
)
def login(
    data: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    ip = client_ip(request)
    account_key = f"{data.email.lower()}|{ip}"

    # Demasiados intentos fallidos: se frena aunque la clave ahora sea buena.
    if login_by_account.is_blocked(account_key) or login_by_ip.is_blocked(ip):
        raise HTTPException(
            status_code=429,
            detail="Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
        )

    user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if not user:
        login_by_account.hit(account_key)
        login_by_ip.hit(ip)
        raise HTTPException(
            status_code=401,
            detail="Correo o contraseña incorrectos",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="El usuario está desactivado",
        )

    if not pwd_context.verify(
        data.password,
        user.password_hash,
    ):
        login_by_account.hit(account_key)
        login_by_ip.hit(ip)
        raise HTTPException(
            status_code=401,
            detail="Correo o contraseña incorrectos",
        )

    login_by_account.reset(account_key)

    access_token = issue_token(user)

    return AuthResponse(
        message="Inicio de sesión correcto",
        user_id=user.id,
        name=user.name,
        email=user.email,
        is_business=user.is_business,
        access_token=access_token,
    )


@router.post(
    "/google",
    response_model=AuthResponse,
)
def google_login(
    data: GoogleLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Inicia sesión (o crea la cuenta) con un Firebase ID token de Google.

    Firebase autentica la cuenta de Google en Flutter. El backend verifica el
    token y entrega el JWT propio de Rescate, así el resto de la API sigue
    usando el mismo mecanismo de sesión.
    """
    ip = client_ip(request)

    if google_fail_by_ip.is_blocked(ip):
        raise HTTPException(
            status_code=429,
            detail="Demasiados intentos. Espera unos minutos e inténtalo de nuevo.",
        )

    try:
        decoded = verify_id_token(data.id_token)
    except HTTPException as error:
        if error.status_code == 401:
            google_fail_by_ip.hit(ip)
        raise

    firebase_uid = decoded.get("uid")
    email = (decoded.get("email") or "").strip().lower()
    name = (decoded.get("name") or "Usuario Google").strip()
    email_verified = bool(decoded.get("email_verified", False))

    if not firebase_uid or not email or not email_verified:
        google_fail_by_ip.hit(ip)
        raise HTTPException(
            status_code=401,
            detail="La cuenta de Google no tiene un correo válido verificado.",
        )

    user = (
        db.query(User)
        .filter(User.firebase_uid == firebase_uid)
        .first()
    )

    # Si ya existía una cuenta con ese correo, se vincula a Google.
    linking_existing = False

    if user is None:
        user = (
            db.query(User)
            .filter(User.email == email)
            .first()
        )
        linking_existing = user is not None

    if user is None:
        # Cuenta nueva: hay que saber si es cliente o negocio.
        if data.is_business is None:
            raise HTTPException(status_code=409, detail="ROLE_REQUIRED")

        user = User(
            name=name[:100] or "Usuario Google",
            email=email[:150],
            # Nunca se usa para entrar; solo mantiene el modelo completo.
            password_hash=pwd_context.hash(secrets.token_urlsafe(48)),
            firebase_uid=firebase_uid,
            auth_provider="google",
            is_business=bool(data.is_business),
            is_active=True,
        )
        db.add(user)

    else:
        if not user.is_active:
            raise HTTPException(
                status_code=403,
                detail="El usuario está desactivado",
            )

        if linking_existing:
            # El registro por correo no verifica que el correo sea de quien
            # lo escribió. Si alguien registró este correo antes que su
            # dueño, no debe conservar el acceso: se anula la contraseña y
            # se cierran las sesiones que ya existían. El dueño real puede
            # crear otra con "Olvidé mi contraseña".
            user.password_hash = pwd_context.hash(secrets.token_urlsafe(48))
            user.token_version = (user.token_version or 0) + 1
            user.firebase_uid = firebase_uid
            user.auth_provider = "google"

    db.commit()
    db.refresh(user)

    return AuthResponse(
        message="Inicio de sesión con Google correcto",
        user_id=user.id,
        name=user.name,
        email=user.email,
        is_business=user.is_business,
        access_token=issue_token(user),
    )


@router.get(
    "/me",
    response_model=AuthResponse,
)
def get_me(
    current_user: User = Depends(get_current_user),
):
    return AuthResponse(
        message="Usuario autenticado",
        user_id=current_user.id,
        name=current_user.name,
        email=current_user.email,
        is_business=current_user.is_business,
        access_token="",
    )


# =========================================================
# ELIMINAR MI CUENTA
# (Obligatorio en Google Play y App Store)
# =========================================================

def _confirm_identity(data: DeleteAccountRequest, user: User) -> None:
    """La persona debe demostrar que es la dueña de la cuenta.

    - Cuentas con contraseña: la contraseña.
    - Cuentas de Google: un token de Google recién obtenido (la app le pide
      volver a elegir su cuenta), de los últimos 5 minutos.
    """
    if data.password:
        if pwd_context.verify(data.password, user.password_hash):
            return

        raise HTTPException(
            status_code=400,
            detail="La contraseña es incorrecta",
        )

    if data.id_token:
        if not user.firebase_uid:
            raise HTTPException(
                status_code=400,
                detail="Esta cuenta no está vinculada a Google",
            )

        try:
            decoded = verify_id_token(data.id_token)
        except HTTPException as error:
            # 400 y no 401: un 401 haría creer a la app que la sesión expiró.
            if error.status_code == 401:
                raise HTTPException(status_code=400, detail=error.detail)
            raise

        if decoded.get("uid") != user.firebase_uid:
            raise HTTPException(
                status_code=400,
                detail="La cuenta de Google no coincide con tu cuenta de Rescate",
            )

        auth_time = decoded.get("auth_time")

        if (
            not isinstance(auth_time, (int, float))
            or time.time() - auth_time > 300
        ):
            raise HTTPException(
                status_code=400,
                detail="Por seguridad, confirma de nuevo con Google e inténtalo otra vez",
            )

        return

    raise HTTPException(
        status_code=400,
        detail="Confirma tu identidad con tu contraseña o con tu cuenta de Google",
    )


@router.post(
    "/delete-account",
    response_model=MessageResponse,
)
def delete_account(
    data: DeleteAccountRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Elimina la cuenta: borra datos personales y anonimiza el historial.

    Las reservas pasadas se conservan sin datos personales (el negocio las
    necesita para su contabilidad). No se puede eliminar la cuenta mientras
    haya reservas pendientes de retiro.
    """
    _confirm_identity(data, current_user)

    expire_overdue_reservations(db)

    business = (
        db.query(Business)
        .filter(Business.owner_id == current_user.id)
        .first()
    )

    # 1) Reservas pendientes que bloquean la eliminacion
    mine = (
        db.query(Reservation)
        .filter(Reservation.user_id == current_user.id)
        .filter(Reservation.status == "reserved")
        .count()
    )

    if mine > 0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Tienes {mine} reserva(s) pendiente(s). Retírala(s) o "
                "cancélala(s) antes de eliminar tu cuenta."
            ),
        )

    if business:
        pending_for_business = (
            db.query(Reservation)
            .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
            .filter(FoodPack.business_id == business.id)
            .filter(Reservation.status == "reserved")
            .count()
        )

        if pending_for_business > 0:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Tu negocio tiene {pending_for_business} reserva(s) de "
                    "clientes pendiente(s) de retiro. Entrégalas antes de "
                    "eliminar tu cuenta."
                ),
            )

    # 2) Google: se borra de Firebase (correo, nombre, foto) ANTES de tocar
    #    la base de datos. Si Firebase falla, se cancela todo y la cuenta
    #    queda intacta para reintentar.
    if current_user.firebase_uid:
        delete_firebase_user(current_user.firebase_uid)

    # 3) Negocio: borrar packs sin historial, ocultar el resto y quitar
    #    datos de contacto y fotos.
    if business:
        packs = (
            db.query(FoodPack)
            .filter(FoodPack.business_id == business.id)
            .all()
        )

        for pack in packs:
            delete_pack_image_file(pack.image_url)

            has_history = (
                db.query(Reservation)
                .filter(Reservation.food_pack_id == pack.id)
                .first()
            )

            if has_history:
                pack.image_url = None
                pack.status = "paused"
            else:
                db.delete(pack)

        business.name = "Negocio eliminado"
        business.description = None
        business.address = "No disponible"
        business.phone = None
        business.latitude = None
        business.longitude = None

    # 4) Usuario: borrar datos personales y bloquear el acceso
    db.query(DeviceToken).filter(
        DeviceToken.user_id == current_user.id
    ).delete()

    current_user.name = "Usuario eliminado"
    current_user.email = f"deleted-{current_user.id}@deleted.invalid"
    current_user.password_hash = pwd_context.hash(secrets.token_urlsafe(32))
    current_user.firebase_uid = None  # libera la identidad de Google
    current_user.auth_provider = "deleted"
    current_user.token_version = (current_user.token_version or 0) + 1
    current_user.is_active = False

    db.commit()

    return MessageResponse(message="Tu cuenta fue eliminada")


# =========================================================
# RECUPERAR CONTRASENA (codigo de 6 digitos por correo)
# =========================================================

RESET_CODE_MINUTES = 10      # vigencia del codigo
RESET_MAX_ATTEMPTS = 5       # intentos por codigo
RESET_MAX_REQUESTS_PER_HOUR = 3

# Misma respuesta exista o no el correo: no se revela quien tiene cuenta.
FORGOT_PASSWORD_MESSAGE = (
    "Si el correo está registrado, te enviamos un código de 6 dígitos. "
    f"Vence en {RESET_CODE_MINUTES} minutos."
)

INVALID_CODE_MESSAGE = "El código es incorrecto o ya venció"


def _hash_reset_code(user_id: int, code: str) -> str:
    """Huella del codigo, atada al usuario y a la SECRET_KEY del servidor."""
    secret = os.getenv("SECRET_KEY", "").encode()

    return hmac.new(
        secret,
        f"{user_id}:{code}".encode(),
        hashlib.sha256,
    ).hexdigest()


@router.post(
    "/forgot-password",
    response_model=MessageResponse,
)
def forgot_password(
    data: ForgotPasswordRequest,
    background_tasks: BackgroundTasks,
    request: Request,
    db: Session = Depends(get_db),
):
    """Envia al correo un codigo de 6 digitos para cambiar la contrasena."""
    ip = client_ip(request)

    # Limite por IP: evita que alguien llene de correos buzones ajenos.
    # Se responde igual para no dar pistas.
    if forgot_by_ip.is_blocked(ip):
        return MessageResponse(message=FORGOT_PASSWORD_MESSAGE)

    forgot_by_ip.hit(ip)

    user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if user and user.is_active:
        now = datetime.utcnow()

        recent = (
            db.query(PasswordReset)
            .filter(PasswordReset.user_id == user.id)
            .filter(PasswordReset.created_at >= now - timedelta(hours=1))
            .count()
        )

        # Pasado el limite se ignora en silencio (misma respuesta).
        if recent < RESET_MAX_REQUESTS_PER_HOUR:
            # Un codigo nuevo invalida los anteriores
            db.query(PasswordReset).filter(
                PasswordReset.user_id == user.id,
                PasswordReset.used.is_(False),
            ).update({"used": True})

            code = f"{secrets.randbelow(10**6):06d}"

            db.add(
                PasswordReset(
                    user_id=user.id,
                    code_hash=_hash_reset_code(user.id, code),
                    expires_at=now + timedelta(minutes=RESET_CODE_MINUTES),
                )
            )
            db.commit()

            # En segundo plano: asi la respuesta tarda lo mismo exista o no
            # el correo.
            background_tasks.add_task(
                send_password_reset_code,
                user.email,
                user.name,
                code,
                RESET_CODE_MINUTES,
            )

    return MessageResponse(message=FORGOT_PASSWORD_MESSAGE)


@router.post(
    "/reset-password",
    response_model=MessageResponse,
)
def reset_password(
    data: ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    """Cambia la contrasena usando el codigo recibido por correo."""
    if len(data.new_password) < 6:
        raise HTTPException(
            status_code=400,
            detail="La contraseña debe tener al menos 6 caracteres",
        )

    user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    invalid = HTTPException(status_code=400, detail=INVALID_CODE_MESSAGE)

    if not user or not user.is_active:
        raise invalid

    # Se bloquea la fila: pruebas simultaneas no pueden saltarse el limite
    # de intentos.
    reset = (
        db.query(PasswordReset)
        .filter(PasswordReset.user_id == user.id)
        .filter(PasswordReset.used.is_(False))
        .order_by(PasswordReset.id.desc())
        .with_for_update()
        .first()
    )

    if not reset or reset.expires_at < datetime.utcnow():
        raise invalid

    if reset.attempts >= RESET_MAX_ATTEMPTS:
        reset.used = True
        db.commit()
        raise invalid

    reset.attempts += 1

    expected = reset.code_hash
    received = _hash_reset_code(user.id, data.code.strip())

    if not hmac.compare_digest(expected, received):
        if reset.attempts >= RESET_MAX_ATTEMPTS:
            reset.used = True
        db.commit()
        raise invalid

    user.password_hash = pwd_context.hash(data.new_password)
    # Cambiar la contrasena cierra todas las sesiones abiertas.
    user.token_version = (user.token_version or 0) + 1
    reset.used = True

    db.query(PasswordReset).filter(
        PasswordReset.user_id == user.id,
        PasswordReset.used.is_(False),
    ).update({"used": True})

    db.commit()

    return MessageResponse(
        message="Tu contraseña fue actualizada. Ya puedes iniciar sesión."
    )
