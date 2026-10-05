from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database import get_db
from models.device_token import DeviceToken
from models.user import User
from schemas.notification import (
    RegisterTokenRequest,
    RegisterTokenResponse,
)
from security import get_current_user


router = APIRouter(
    prefix="/api/notifications",
    tags=["Notifications"],
)


@router.post(
    "/register-token",
    response_model=RegisterTokenResponse,
)
def register_token(
    data: RegisterTokenRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    existing = (
        db.query(DeviceToken)
        .filter(DeviceToken.token == data.token)
        .first()
    )

    if existing:
        existing.user_id = current_user.id
        existing.platform = data.platform
        db.commit()

        return RegisterTokenResponse(
            message="Token actualizado correctamente"
        )

    new_token = DeviceToken(
        user_id=current_user.id,
        token=data.token,
        platform=data.platform,
    )

    db.add(new_token)
    db.commit()

    return RegisterTokenResponse(
        message="Token registrado correctamente"
    )