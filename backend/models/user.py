from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        primary_key=True,
        index=True,
    )

    name: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
    )

    email: Mapped[str] = mapped_column(
        String(150),
        unique=True,
        index=True,
        nullable=False,
    )

    password_hash: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    # Identidad Firebase usada por inicio de sesión con Google.
    # Es nullable porque las cuentas existentes pueden seguir usando
    # correo + contraseña.
    firebase_uid: Mapped[str | None] = mapped_column(
        String(128),
        unique=True,
        index=True,
        nullable=True,
    )

    auth_provider: Mapped[str] = mapped_column(
        String(30),
        default="password",
        nullable=False,
    )

    # Se suma 1 para cerrar TODAS las sesiones abiertas de esta cuenta
    # (los JWT guardan la version con la que se emitieron).
    token_version: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default="0",
        nullable=False,
    )

    is_business: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        nullable=False,
    )