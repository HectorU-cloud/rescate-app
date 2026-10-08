import secrets
from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.business import Business
from models.food_pack import FoodPack
from models.reservation import Reservation
from models.user import User
from reservation_rules import (
    NO_SHOW_LIMIT,
    NO_SHOW_WINDOW_DAYS,
    expire_overdue_reservations,
    is_blocked_for_no_shows,
)
from schemas.reservation import (
    ReservationCreate,
    ReservationResponse,
    UnseenCountResponse,
)
from security import get_current_user


router = APIRouter(
    prefix="/api/reservations",
    tags=["Reservations"],
)


SERVICE_FEE = Decimal("0.25")

# Metodos de pago que el servidor acepta. "online" NO esta aqui a proposito:
# una reserva "pagada online" sin cobro real regalaria la comida. Se agrega
# cuando exista un pago verificado (Payphone).
ACCEPTED_PAYMENT_METHODS = ("cash",)


def _reservation_code(db: Session) -> str:
    for _ in range(10):
        code = f"RES-{secrets.token_hex(4).upper()}"

        exists = (
            db.query(Reservation)
            .filter(Reservation.reservation_code == code)
            .first()
        )

        if not exists:
            return code

    raise HTTPException(
        status_code=500,
        detail="No se pudo generar el código de reserva",
    )


def _build_reservation_response(
    reservation: Reservation,
    pack: FoodPack,
    business: Business,
    customer: User | None = None,
) -> dict:
    return {
        "id": reservation.id,
        "reservation_code": reservation.reservation_code,
        "user_id": reservation.user_id,
        "food_pack_id": reservation.food_pack_id,
        "quantity": reservation.quantity,
        "total": float(reservation.total),
        "status": reservation.status,
        "created_at": reservation.created_at,

        "payment_method": reservation.payment_method,
        "service_fee": float(reservation.service_fee),
        "amount_to_collect": float(reservation.amount_to_collect),
        "fee_settled": reservation.fee_settled,
        "seen_by_business": reservation.seen_by_business,

        "business_name": business.name,
        "title": pack.title,
        "description": pack.description,
        "price": float(pack.price),
        "original_price": float(pack.original_price),
        "pickup_start": pack.pickup_start,
        "pickup_end": pack.pickup_end,
        "address": business.address,

        "business_latitude": business.latitude,
        "business_longitude": business.longitude,

        "customer_name": customer.name if customer else "Cliente",
    }


def _get_business_of_user(
    current_user: User,
    db: Session,
) -> Business:
    business = (
        db.query(Business)
        .filter(Business.owner_id == current_user.id)
        .first()
    )

    if not business:
        raise HTTPException(
            status_code=404,
            detail="No tienes un negocio registrado",
        )

    return business


# =========================================================
# CLIENTE: mis reservas
# =========================================================

@router.get(
    "",
    response_model=list[ReservationResponse],
)
def get_reservations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    expire_overdue_reservations(db)

    rows = (
        db.query(Reservation, FoodPack, Business)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .join(Business, FoodPack.business_id == Business.id)
        .filter(Reservation.user_id == current_user.id)
        .order_by(Reservation.created_at.desc())
        .all()
    )

    return [
        _build_reservation_response(r, p, b, customer=current_user)
        for r, p, b in rows
    ]


# =========================================================
# NEGOCIO: reservas recibidas
# ⚠️ Antes de /{reservation_id}
# =========================================================

@router.get(
    "/received",
    response_model=list[ReservationResponse],
)
def get_received_reservations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    expire_overdue_reservations(db)

    rows = (
        db.query(Reservation, FoodPack, Business, User)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .join(Business, FoodPack.business_id == Business.id)
        .join(User, Reservation.user_id == User.id)
        .filter(Business.id == business.id)
        .order_by(Reservation.created_at.desc())
        .all()
    )

    return [
        _build_reservation_response(r, p, b, customer=c)
        for r, p, b, c in rows
    ]


# =========================================================
# NEGOCIO: contador de no vistas
# =========================================================

@router.get(
    "/unseen-count",
    response_model=UnseenCountResponse,
)
def get_unseen_count(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    count = (
        db.query(Reservation)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .filter(FoodPack.business_id == business.id)
        .filter(Reservation.seen_by_business == False)
        .count()
    )

    return UnseenCountResponse(count=count)


# =========================================================
# NEGOCIO: marcar todas como vistas
# =========================================================

@router.post(
    "/mark-seen",
    response_model=UnseenCountResponse,
)
def mark_all_seen(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    unseen = (
        db.query(Reservation)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .filter(FoodPack.business_id == business.id)
        .filter(Reservation.seen_by_business == False)
        .all()
    )

    for r in unseen:
        r.seen_by_business = True

    db.commit()

    return UnseenCountResponse(count=0)


# =========================================================
# Ver UNA reserva
# =========================================================

@router.get(
    "/{reservation_id}",
    response_model=ReservationResponse,
)
def get_reservation(
    reservation_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = (
        db.query(Reservation, FoodPack, Business)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .join(Business, FoodPack.business_id == Business.id)
        .filter(Reservation.id == reservation_id)
        .first()
    )

    if not row:
        raise HTTPException(
            status_code=404,
            detail="Reserva no encontrada",
        )

    reservation, pack, business = row

    if (
        reservation.user_id != current_user.id
        and business.owner_id != current_user.id
    ):
        raise HTTPException(
            status_code=403,
            detail="No autorizado para ver esta reserva",
        )

    customer = (
        db.query(User)
        .filter(User.id == reservation.user_id)
        .first()
    )

    return _build_reservation_response(
        reservation, pack, business, customer=customer
    )


# =========================================================
# CLIENTE: crear reserva
# =========================================================

@router.post(
    "",
    response_model=ReservationResponse,
    status_code=201,
)
def create_reservation(
    data: ReservationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Quien dejo varias reservas sin retirar queda bloqueado un tiempo.
    expire_overdue_reservations(db)

    if is_blocked_for_no_shows(db, current_user.id):
        raise HTTPException(
            status_code=403,
            detail=(
                f"Tienes {NO_SHOW_LIMIT} reservas sin retirar en los últimos "
                f"{NO_SHOW_WINDOW_DAYS} días, por eso no puedes reservar "
                "por ahora. Retira a tiempo o cancela con anticipación."
            ),
        )

    # Bloquea la fila del pack hasta el commit: si dos personas reservan
    # a la vez, la segunda espera y ve el stock ya descontado.
    pack = (
        db.query(FoodPack)
        .filter(FoodPack.id == data.food_pack_id)
        .with_for_update()
        .first()
    )

    if not pack:
        raise HTTPException(
            status_code=404,
            detail="Pack no encontrado",
        )

    business = (
        db.query(Business)
        .filter(Business.id == pack.business_id)
        .first()
    )

    if not business:
        raise HTTPException(
            status_code=404,
            detail="Negocio no encontrado",
        )

    if pack.status != "available":
        raise HTTPException(
            status_code=400,
            detail="El pack ya no está disponible",
        )

    # Los horarios se guardan en UTC sin zona horaria (ver routers/packs.py).
    if pack.pickup_end <= datetime.utcnow():
        raise HTTPException(
            status_code=400,
            detail="El horario de retiro de este pack ya terminó",
        )

    if data.quantity > pack.quantity:
        raise HTTPException(
            status_code=400,
            detail="No hay suficientes unidades disponibles",
        )

    if data.payment_method not in ACCEPTED_PAYMENT_METHODS:
        raise HTTPException(
            status_code=400,
            detail="Por ahora solo se acepta pago en efectivo al retirar",
        )

    subtotal = Decimal(str(pack.price)) * data.quantity
    service_fee = SERVICE_FEE
    total = subtotal + service_fee
    amount_to_collect = total if data.payment_method == "cash" else Decimal("0")

    reservation = Reservation(
        reservation_code=_reservation_code(db),
        user_id=current_user.id,
        food_pack_id=data.food_pack_id,
        quantity=data.quantity,
        total=total,
        status="reserved",
        payment_method=data.payment_method,
        service_fee=service_fee,
        amount_to_collect=amount_to_collect,
        fee_settled=False,
        seen_by_business=False,  # 👈 explícito
    )

    pack.quantity -= data.quantity

    if pack.quantity == 0:
        pack.status = "sold_out"

    db.add(reservation)
    db.commit()
    db.refresh(reservation)

        # 🔔 Notificar al negocio
    try:
        from firebase_service import send_push_to_user

        send_push_to_user(
            db=db,
            user_id=business.owner_id,
            title="🛒 Nueva reserva",
            body=f"{current_user.name} reservó {data.quantity}x {pack.title}",
            data={
                "type": "new_reservation",
                "reservation_code": reservation.reservation_code,
            },
        )
    except Exception as error:
        print(f"⚠️ No se pudo enviar notificación: {error}")

    return _build_reservation_response(
        reservation, pack, business, customer=current_user
    )


# =========================================================
# CLIENTE: cancelar reserva
# =========================================================

@router.patch(
    "/{reservation_id}/cancel",
    response_model=ReservationResponse,
)
def cancel_reservation(
    reservation_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Bloquea reserva y pack: un doble toque en "Cancelar" no debe
    # devolver el stock dos veces.
    row = (
        db.query(Reservation, FoodPack, Business)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .join(Business, FoodPack.business_id == Business.id)
        .filter(Reservation.id == reservation_id)
        .with_for_update(of=(Reservation, FoodPack))
        .first()
    )

    if not row:
        raise HTTPException(
            status_code=404,
            detail="Reserva no encontrada",
        )

    reservation, pack, business = row

    if reservation.user_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="No autorizado para cancelar esta reserva",
        )

    if reservation.status != "reserved":
        raise HTTPException(
            status_code=400,
            detail="La reserva no se puede cancelar",
        )

    pack.quantity += reservation.quantity

    if pack.status == "sold_out":
        pack.status = "available"

    reservation.status = "cancelled"

    db.commit()
    db.refresh(reservation)

        # 🔔 Notificar al negocio sobre la cancelación
    try:
        from firebase_service import send_push_to_user

        send_push_to_user(
            db=db,
            user_id=business.owner_id,
            title="❌ Reserva cancelada",
            body=f"{current_user.name} canceló {reservation.quantity}x {pack.title}",
            data={
                "type": "cancelled",
                "reservation_code": reservation.reservation_code,
            },
        )
    except Exception as error:
        print(f"⚠️ No se pudo enviar notificación: {error}")

    return _build_reservation_response(
        reservation, pack, business, customer=current_user
    )


# =========================================================
# NEGOCIO: validar QR
# =========================================================

@router.post(
    "/{reservation_code}/validate",
    response_model=ReservationResponse,
)
def validate_reservation(
    reservation_code: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    expire_overdue_reservations(db)

    reservation = (
        db.query(Reservation)
        .filter(Reservation.reservation_code == reservation_code)
        .with_for_update()
        .first()
    )

    if not reservation:
        raise HTTPException(
            status_code=404,
            detail="Reserva no encontrada",
        )

    pack = (
        db.query(FoodPack)
        .filter(FoodPack.id == reservation.food_pack_id)
        .first()
    )

    business = (
        db.query(Business)
        .filter(Business.id == pack.business_id)
        .first()
    )

    if business.owner_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="No autorizado para validar esta reserva",
        )

    if reservation.status == "no_show":
        raise HTTPException(
            status_code=400,
            detail="Esta reserva venció: no se retiró dentro del horario",
        )

    if reservation.status == "picked_up":
        raise HTTPException(
            status_code=400,
            detail="Esta reserva ya fue validada",
        )

    if reservation.status != "reserved":
        raise HTTPException(
            status_code=400,
            detail=f"La reserva no se puede validar (estado: {reservation.status})",
        )

    reservation.status = "picked_up"

    if reservation.payment_method == "cash":
        reservation.amount_to_collect = Decimal("0")

    db.commit()
    db.refresh(reservation)

        # 🔔 Notificar al cliente
    try:
        from firebase_service import send_push_to_user

        send_push_to_user(
            db=db,
            user_id=reservation.user_id,
            title="✅ ¡Rescate completado!",
            body=f"Tu pack '{pack.title}' fue entregado. ¡Gracias!",
            data={
                "type": "validated",
                "reservation_code": reservation.reservation_code,
            },
        )
    except Exception as error:
        print(f"⚠️ No se pudo enviar notificación: {error}")

    customer = (
        db.query(User)
        .filter(User.id == reservation.user_id)
        .first()
    )

    return _build_reservation_response(
        reservation, pack, business, customer=customer
    )