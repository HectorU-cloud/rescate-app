from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ReservationCreate(BaseModel):
    food_pack_id: int
    quantity: int = Field(gt=0)
    payment_method: str = "online"


class ReservationResponse(BaseModel):
    id: int
    reservation_code: str
    user_id: int
    food_pack_id: int
    quantity: int
    total: float
    status: str
    created_at: datetime

    payment_method: str
    service_fee: float
    amount_to_collect: float
    fee_settled: bool

    # 👇 NUEVO
    seen_by_business: bool

    business_name: str
    title: str
    description: str | None
    price: float
    original_price: float
    pickup_start: datetime
    pickup_end: datetime
    address: str

    business_latitude: float | None = None
    business_longitude: float | None = None

    customer_name: str

    model_config = ConfigDict(from_attributes=True)


# 👇 NUEVO
class UnseenCountResponse(BaseModel):
    count: int