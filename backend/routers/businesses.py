from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.business import Business
from models.food_pack import FoodPack
from models.reservation import Reservation
from models.user import User
from schemas.business import (
    BusinessCreate,
    BusinessResponse,
    BusinessStats,
    SettleFeesResponse,
)
from security import get_current_user


router = APIRouter(
    prefix="/api/businesses",
    tags=["Businesses"],
)


# =========================================================
# LISTAR NEGOCIOS (PÚBLICO)
# =========================================================

@router.get(
    "",
    response_model=list[BusinessResponse],
)
def get_businesses(
    db: Session = Depends(get_db),
):
    return (
        db.query(Business)
        .order_by(Business.name)
        .all()
    )


# =========================================================
# MI NEGOCIO
# =========================================================

@router.get(
    "/me",
    response_model=BusinessResponse,
)
def get_my_business(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
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
# ESTADÍSTICAS
# =========================================================

@router.get(
    "/me/stats",
    response_model=BusinessStats,
)
def get_my_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
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

    all_packs = (
        db.query(FoodPack)
        .filter(FoodPack.business_id == business.id)
        .all()
    )

    total_packs = len(all_packs)
    available_packs = sum(1 for p in all_packs if p.status == "available")
    sold_out_packs = sum(1 for p in all_packs if p.status == "sold_out")
    paused_packs = sum(1 for p in all_packs if p.status == "paused")

    reservations = (
        db.query(Reservation)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .filter(FoodPack.business_id == business.id)
        .all()
    )

    total_reservations = len(reservations)
    completed_reservations = sum(
        1 for r in reservations if r.status == "picked_up"
    )
    pending_reservations = sum(
        1 for r in reservations if r.status == "reserved"
    )
    cancelled_reservations = sum(
        1 for r in reservations if r.status == "cancelled"
    )

    active_reservations = [
        r for r in reservations if r.status != "cancelled"
    ]

    total_revenue = sum(
        float(r.total) - float(r.service_fee)
        for r in active_reservations
    )

    # 🏦 Deuda pendiente: reservas en efectivo ya cobradas, sin liquidar
    pending_fee_debt = sum(
        float(r.service_fee)
        for r in active_reservations
        if r.payment_method == "cash"
        and r.status == "picked_up"
        and not r.fee_settled
    )

    total_saved = 0.0
    pack_cache = {p.id: p for p in all_packs}

    for r in active_reservations:
        pack = pack_cache.get(r.food_pack_id)
        if pack:
            total_saved += float(pack.original_price) * r.quantity

    today = datetime.utcnow().date()

    today_active = [
        r for r in active_reservations
        if r.created_at and r.created_at.date() == today
    ]

    today_reservations = len(today_active)
    today_revenue = sum(
        float(r.total) - float(r.service_fee)
        for r in today_active
    )

    return BusinessStats(
        total_packs=total_packs,
        available_packs=available_packs,
        sold_out_packs=sold_out_packs,
        paused_packs=paused_packs,
        total_reservations=total_reservations,
        completed_reservations=completed_reservations,
        pending_reservations=pending_reservations,
        cancelled_reservations=cancelled_reservations,
        total_revenue=round(total_revenue, 2),
        total_saved=round(total_saved, 2),
        today_reservations=today_reservations,
        today_revenue=round(today_revenue, 2),
        pending_fee_debt=round(pending_fee_debt, 2),
    )


# =========================================================
# LIQUIDAR COMISIONES
# =========================================================

@router.post(
    "/me/settle-fees",
    response_model=SettleFeesResponse,
)
def settle_fees(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
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

    # Buscar reservas con servicio pendiente de liquidar
    pending = (
        db.query(Reservation)
        .join(FoodPack, Reservation.food_pack_id == FoodPack.id)
        .filter(FoodPack.business_id == business.id)
        .filter(Reservation.payment_method == "cash")
        .filter(Reservation.status == "picked_up")
        .filter(Reservation.fee_settled == False)
        .all()
    )

    if not pending:
        return SettleFeesResponse(
            message="No tienes comisiones pendientes de liquidar",
            settled_count=0,
            settled_amount=0.0,
        )

    total_settled = sum(float(r.service_fee) for r in pending)

    for r in pending:
        r.fee_settled = True

    db.commit()

    return SettleFeesResponse(
        message=f"Se liquidaron {len(pending)} comisiones correctamente",
        settled_count=len(pending),
        settled_amount=round(total_settled, 2),
    )


# =========================================================
# OBTENER UN NEGOCIO POR ID
# =========================================================

@router.get(
    "/{business_id}",
    response_model=BusinessResponse,
)
def get_business(
    business_id: int,
    db: Session = Depends(get_db),
):
    business = (
        db.query(Business)
        .filter(Business.id == business_id)
        .first()
    )

    if not business:
        raise HTTPException(
            status_code=404,
            detail="Negocio no encontrado",
        )

    return business


# =========================================================
# CREAR NEGOCIO
# =========================================================

@router.post(
    "",
    response_model=BusinessResponse,
    status_code=201,
)
def create_business(
    business: BusinessCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not current_user.is_business:
        raise HTTPException(
            status_code=400,
            detail="El usuario no está registrado como negocio",
        )

    existing = (
        db.query(Business)
        .filter(Business.owner_id == current_user.id)
        .first()
    )

    if existing:
        raise HTTPException(
            status_code=400,
            detail="Ya tienes un negocio registrado",
        )

    new_business = Business(
        owner_id=current_user.id,
        name=business.name,
        description=business.description,
        address=business.address,
        city=business.city,
        latitude=business.latitude,
        longitude=business.longitude,
        phone=business.phone,
    )

    db.add(new_business)
    db.commit()
    db.refresh(new_business)

    return new_business