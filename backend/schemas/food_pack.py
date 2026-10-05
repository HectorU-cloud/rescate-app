from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator


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


def _check_image_url(value: str | None) -> str | None:
    # Import local para evitar dependencias circulares al cargar los schemas.
    from routers.uploads import is_valid_pack_image_url

    if not is_valid_pack_image_url(value):
        raise ValueError("image_url debe ser una foto subida con /api/uploads/pack-image")
    return value


class FoodPackCreate(FoodPackBase):
    @field_validator("image_url")
    @classmethod
    def validate_image_url(cls, value):
        return _check_image_url(value)


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

    @field_validator("image_url")
    @classmethod
    def validate_image_url(cls, value):
        return _check_image_url(value)


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