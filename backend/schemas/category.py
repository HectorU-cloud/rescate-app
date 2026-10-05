from pydantic import BaseModel, ConfigDict


class CategoryBase(BaseModel):
    name: str
    icon: str | None = None


class CategoryCreate(CategoryBase):
    pass


class CategoryResponse(CategoryBase):
    id: int

    model_config = ConfigDict(from_attributes=True)