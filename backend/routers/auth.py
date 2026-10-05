from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from database import get_db
from models.user import User
from schemas.auth import (
    RegisterRequest,
    LoginRequest,
    AuthResponse,
)
from security import create_access_token, get_current_user


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

    access_token = create_access_token(
        data={"sub": str(new_user.id)},
    )

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
    db: Session = Depends(get_db),
):
    user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if not user:
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
        raise HTTPException(
            status_code=401,
            detail="Correo o contraseña incorrectos",
        )

    access_token = create_access_token(
        data={"sub": str(user.id)},
    )

    return AuthResponse(
        message="Inicio de sesión correcto",
        user_id=user.id,
        name=user.name,
        email=user.email,
        is_business=user.is_business,
        access_token=access_token,
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