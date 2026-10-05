from datetime import datetime

from pydantic import BaseModel, ConfigDict


class FoodPackBase(BaseModel):
    category_id: int
    title: str
    description: str | None = None
    price: float
    original_price: float
    quantity: int
    pickup_start: datetime
    pickup_end: datetime
    image_url: str | None = None


class FoodPackCreate(FoodPackBase):
    pass


# 👇 NUEVO: todos los campos opcionales para actualización parcial
class FoodPackUpdate(BaseModel):
    category_id: int | None = None
    title: str | None = None
    description: str | None = None
    price: float | None = None
    original_price: float | None = None
    quantity: int | None = None
    pickup_start: datetime | None = None
    pickup_end: datetime | None = None
    image_url: str | None = None
    status: str | None = None  # available, sold_out, paused, expired


class FoodPackResponse(BaseModel):
    id: int
    business_id: int
    category_id: int

    business_name: str
    category_name: str
    address: str

    business_latitude: float | None = None
    business_longitude: float | None = None

    title: str
    description: str | None
    price: float
    original_price: float
    quantity: int
    pickup_start: datetime
    pickup_end: datetime
    status: str
    image_url: str | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)