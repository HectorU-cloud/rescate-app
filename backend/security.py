import os
from datetime import datetime, timedelta, timezone

import jwt
from jwt.exceptions import InvalidTokenError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from database import get_db
from models.user import User


SECRET_KEY = os.getenv("SECRET_KEY")

if not SECRET_KEY or len(SECRET_KEY) < 32:
    raise RuntimeError(
        "SECRET_KEY no está configurada o es muy corta (mínimo 32 caracteres). "
        "Genera una con: python -c \"import secrets; print(secrets.token_urlsafe(48))\""
    )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 días


# 👇 CAMBIO CLAVE: HTTPBearer en vez de OAuth2PasswordBearer
bearer_scheme = HTTPBearer()


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def issue_token(user: User) -> str:
    """JWT de sesion. Guarda la version: si cambia, el token deja de servir."""
    return create_access_token(
        data={"sub": str(user.id), "ver": user.token_version or 0},
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudieron validar las credenciales",
        headers={"WWW-Authenticate": "Bearer"},
    )

    token = credentials.credentials

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id_raw = payload.get("sub")

        if user_id_raw is None:
            raise credentials_exception

        user_id = int(user_id_raw)
        token_version = int(payload.get("ver", 0))

    except (InvalidTokenError, ValueError, TypeError):
        raise credentials_exception

    user = db.query(User).filter(User.id == user_id).first()

    if user is None:
        raise credentials_exception

    # Sesiones cerradas (cambio de contrasena, vinculacion con Google...)
    if token_version != (user.token_version or 0):
        raise credentials_exception

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="El usuario está desactivado",
        )

    return user