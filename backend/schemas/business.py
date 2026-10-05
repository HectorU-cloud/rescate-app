from pydantic import BaseModel, ConfigDict


class BusinessBase(BaseModel):
    name: str
    description: str | None = None
    address: str
    city: str
    latitude: float | None = None
    longitude: float | None = None
    phone: str | None = None


class BusinessCreate(BusinessBase):
    pass


class BusinessResponse(BusinessBase):
    id: int
    owner_id: int

    model_config = ConfigDict(from_attributes=True)


class BusinessStats(BaseModel):
    total_packs: int
    available_packs: int
    sold_out_packs: int
    paused_packs: int

    total_reservations: int
    completed_reservations: int
    pending_reservations: int
    cancelled_reservations: int

    total_revenue: float
    total_saved: float

    today_reservations: int
    today_revenue: float

    pending_fee_debt: float


# 👇 NUEVO
class SettleFeesResponse(BaseModel):
    message: str
    settled_count: int
    settled_amount: float