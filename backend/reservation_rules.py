"""Reglas de reservas que no se retiran ("no show").

No hay un proceso programado: las reservas vencidas se marcan cuando alguien
consulta o crea reservas (ver `expire_overdue_reservations`). Asi no hace
falta un cron ni un worker aparte.

Se puede ajustar desde el .env:
    NO_SHOW_GRACE_MINUTES  minutos extra tras terminar el horario de retiro (30)
    NO_SHOW_LIMIT          no retiros permitidos en la ventana antes de
                           bloquear nuevas reservas; 0 desactiva el bloqueo (3)
    NO_SHOW_WINDOW_DAYS    dias que cuenta cada no retiro (30)
"""
import os
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from models.food_pack import FoodPack
from models.reservation import Reservation


def _int_env(name: str, default: int) -> int:
    try:
        return max(0, int(os.getenv(name, default)))
    except ValueError:
        return default


NO_SHOW_GRACE_MINUTES = _int_env("NO_SHOW_GRACE_MINUTES", 30)
NO_SHOW_LIMIT = _int_env("NO_SHOW_LIMIT", 3)
NO_SHOW_WINDOW_DAYS = _int_env("NO_SHOW_WINDOW_DAYS", 30)

# Estados que no cuentan como venta (ni ingresos ni ahorro).
INACTIVE_STATUSES = ("cancelled", "no_show")


def expire_overdue_reservations(db: Session) -> int:
    """Marca como `no_show` las reservas cuyo horario de retiro ya paso.

    No devuelve el stock: la comida de un horario vencido ya no se vende.
    Devuelve cuantas reservas cambio.
    """
    cutoff = datetime.utcnow() - timedelta(minutes=NO_SHOW_GRACE_MINUTES)

    result = db.execute(
        update(Reservation)
        .where(Reservation.status == "reserved")
        .where(
            Reservation.food_pack_id.in_(
                select(FoodPack.id).where(FoodPack.pickup_end < cutoff)
            )
        )
        .values(status="no_show")
    )
    db.commit()

    return result.rowcount or 0


def recent_no_shows(db: Session, user_id: int) -> int:
    since = datetime.utcnow() - timedelta(days=NO_SHOW_WINDOW_DAYS)

    return (
        db.query(Reservation)
        .filter(Reservation.user_id == user_id)
        .filter(Reservation.status == "no_show")
        .filter(Reservation.created_at >= since)
        .count()
    )


def is_blocked_for_no_shows(db: Session, user_id: int) -> bool:
    if NO_SHOW_LIMIT <= 0:
        return False

    return recent_no_shows(db, user_id) >= NO_SHOW_LIMIT
