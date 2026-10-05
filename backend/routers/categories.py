from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from models.category import Category
from schemas.category import CategoryCreate, CategoryResponse


router = APIRouter(
    prefix="/api/categories",
    tags=["Categories"],
)


@router.get(
    "",
    response_model=list[CategoryResponse],
)
def get_categories(
    db: Session = Depends(get_db),
):
    return (
        db.query(Category)
        .order_by(Category.name)
        .all()
    )


@router.post(
    "",
    response_model=CategoryResponse,
    status_code=201,
)
def create_category(
    category: CategoryCreate,
    db: Session = Depends(get_db),
):
    existing = (
        db.query(Category)
        .filter(Category.name == category.name)
        .first()
    )

    if existing:
        raise HTTPException(
            status_code=400,
            detail="La categoría ya existe",
        )

    new_category = Category(
        name=category.name,
        icon=category.icon,
    )

    db.add(new_category)
    db.commit()
    db.refresh(new_category)

    return new_category