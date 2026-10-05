from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.food_pack import FoodPack
from models.business import Business
from models.category import Category
from models.user import User
from schemas.food_pack import (
    FoodPackCreate,
    FoodPackUpdate,
    FoodPackResponse,
)
from security import get_current_user


router = APIRouter(prefix="/api/packs", tags=["Food Packs"])



def _to_utc_naive(dt: datetime | None) -> datetime | None:
    """Convierte un datetime tz-aware a UTC naive para columnas sin timezone."""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def build_pack_response(
    pack: FoodPack,
    business: Business,
    category: Category,
) -> dict:
    return {
        "id": pack.id,
        "business_id": pack.business_id,
        "category_id": pack.category_id,

        "business_name": business.name,
        "category_name": category.name,
        "address": business.address,

        "business_latitude": business.latitude,
        "business_longitude": business.longitude,

        "title": pack.title,
        "description": pack.description,
        "price": float(pack.price),
        "original_price": float(pack.original_price),
        "quantity": pack.quantity,
        "pickup_start": pack.pickup_start,
        "pickup_end": pack.pickup_end,
        "status": pack.status,
        "image_url": pack.image_url,
        "created_at": pack.created_at,
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
# LISTAR PACKS PÚBLICOS
# =========================================================

@router.get("", response_model=list[FoodPackResponse])
def get_packs(db: Session = Depends(get_db)):
    now = datetime.utcnow()

    rows = (
        db.query(FoodPack, Business, Category)
        .join(Business, FoodPack.business_id == Business.id)
        .join(Category, FoodPack.category_id == Category.id)
        .filter(FoodPack.status == "available")
        .filter(FoodPack.pickup_end > now)
        .order_by(FoodPack.created_at.desc())
        .all()
    )

    return [
        build_pack_response(pack, business, category)
        for pack, business, category in rows
    ]


# =========================================================
# MIS PACKS (NEGOCIO)
# =========================================================

@router.get("/me", response_model=list[FoodPackResponse])
def get_my_packs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    rows = (
        db.query(FoodPack, Business, Category)
        .join(Business, FoodPack.business_id == Business.id)
        .join(Category, FoodPack.category_id == Category.id)
        .filter(FoodPack.business_id == business.id)
        .order_by(FoodPack.created_at.desc())
        .all()
    )

    return [
        build_pack_response(pack, business, category)
        for pack, business, category in rows
    ]


# =========================================================
# OBTENER UN PACK
# =========================================================

@router.get("/{pack_id}", response_model=FoodPackResponse)
def get_pack(pack_id: int, db: Session = Depends(get_db)):
    row = (
        db.query(FoodPack, Business, Category)
        .join(Business, FoodPack.business_id == Business.id)
        .join(Category, FoodPack.category_id == Category.id)
        .filter(FoodPack.id == pack_id)
        .first()
    )

    if not row:
        raise HTTPException(
            status_code=404,
            detail="Pack no encontrado",
        )

    pack, business, category = row

    return build_pack_response(pack, business, category)


# =========================================================
# CREAR PACK
# =========================================================

@router.post("", response_model=FoodPackResponse, status_code=201)
def create_pack(
    pack: FoodPackCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    category = (
        db.query(Category)
        .filter(Category.id == pack.category_id)
        .first()
    )

    if not category:
        raise HTTPException(
            status_code=404,
            detail="Categoría no encontrada",
        )

    if pack.price <= 0:
        raise HTTPException(
            status_code=400,
            detail="El precio debe ser mayor que 0",
        )

    if pack.original_price < pack.price:
        raise HTTPException(
            status_code=400,
            detail="El precio original no puede ser menor que el precio del pack",
        )

    if pack.quantity <= 0:
        raise HTTPException(
            status_code=400,
            detail="La cantidad debe ser mayor que 0",
        )

    if pack.pickup_end <= pack.pickup_start:
        raise HTTPException(
            status_code=400,
            detail="El horario de recogida no es válido",
        )

    new_pack = FoodPack(
        business_id=business.id,
        category_id=pack.category_id,
        title=pack.title,
        description=pack.description,
        price=pack.price,
        original_price=pack.original_price,
        quantity=pack.quantity,
        pickup_start=_to_utc_naive(pack.pickup_start),
        pickup_end=_to_utc_naive(pack.pickup_end),
        image_url=pack.image_url,
        status="available",
    )

    db.add(new_pack)
    db.commit()
    db.refresh(new_pack)

    return build_pack_response(new_pack, business, category)


# =========================================================
# ACTUALIZAR PACK (PARCIAL)
# =========================================================

@router.put("/{pack_id}", response_model=FoodPackResponse)
def update_pack(
    pack_id: int,
    data: FoodPackUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    pack = (
        db.query(FoodPack)
        .filter(FoodPack.id == pack_id)
        .first()
    )

    if not pack:
        raise HTTPException(
            status_code=404,
            detail="Pack no encontrado",
        )

    if pack.business_id != business.id:
        raise HTTPException(
            status_code=403,
            detail="No autorizado para editar este pack",
        )

    # Aplicar solo los campos enviados
    update_data = data.model_dump(exclude_unset=True)

    # Validar category_id si viene
    if "category_id" in update_data:
        category = (
            db.query(Category)
            .filter(Category.id == update_data["category_id"])
            .first()
        )
        if not category:
            raise HTTPException(
                status_code=404,
                detail="Categoría no encontrada",
            )

    # Validaciones de negocio
    new_price = update_data.get("price", float(pack.price))
    new_original_price = update_data.get(
        "original_price", float(pack.original_price)
    )
    new_quantity = update_data.get("quantity", pack.quantity)
    new_start = update_data.get("pickup_start", pack.pickup_start)
    new_end = update_data.get("pickup_end", pack.pickup_end)

    if new_price <= 0:
        raise HTTPException(
            status_code=400,
            detail="El precio debe ser mayor que 0",
        )

    if new_original_price < new_price:
        raise HTTPException(
            status_code=400,
            detail="El precio original no puede ser menor que el precio del pack",
        )

    if new_quantity <= 0:
        raise HTTPException(
            status_code=400,
            detail="La cantidad debe ser mayor que 0",
        )

    if new_end <= new_start:
        raise HTTPException(
            status_code=400,
            detail="El horario de recogida no es válido",
        )

    if "status" in update_data:
        valid_statuses = {"available", "sold_out", "paused", "expired"}
        if update_data["status"] not in valid_statuses:
            raise HTTPException(
                status_code=400,
                detail=f"Estado inválido. Debe ser uno de: {valid_statuses}",
            )

    # Convertir fechas a UTC naive
    if "pickup_start" in update_data:
        update_data["pickup_start"] = _to_utc_naive(update_data["pickup_start"])
    if "pickup_end" in update_data:
        update_data["pickup_end"] = _to_utc_naive(update_data["pickup_end"])

    # Aplicar cambios
    for field, value in update_data.items():
        setattr(pack, field, value)

    db.commit()
    db.refresh(pack)

    category = (
        db.query(Category)
        .filter(Category.id == pack.category_id)
        .first()
    )

    return build_pack_response(pack, business, category)


# =========================================================
# ELIMINAR PACK
# =========================================================

@router.delete("/{pack_id}", status_code=204)
def delete_pack(
    pack_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = _get_business_of_user(current_user, db)

    pack = (
        db.query(FoodPack)
        .filter(FoodPack.id == pack_id)
        .first()
    )

    if not pack:
        raise HTTPException(
            status_code=404,
            detail="Pack no encontrado",
        )

    if pack.business_id != business.id:
        raise HTTPException(
            status_code=403,
            detail="No autorizado para eliminar este pack",
        )

    # Verificar si tiene reservas activas
    from models.reservation import Reservation

    active_reservations = (
        db.query(Reservation)
        .filter(Reservation.food_pack_id == pack_id)
        .filter(Reservation.status == "reserved")
        .count()
    )

    if active_reservations > 0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"No puedes eliminar este pack porque tiene "
                f"{active_reservations} reserva(s) activa(s). "
                "Pausalo en lugar de eliminarlo."
            ),
        )

    db.delete(pack)
    db.commit()

    return None