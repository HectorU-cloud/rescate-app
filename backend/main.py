from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import engine, Base

from models.user import User
from models.category import Category
from models.business import Business
from models.food_pack import FoodPack
from models.reservation import Reservation

from routers.categories import router as categories_router
from routers.packs import router as packs_router
from routers.businesses import router as businesses_router
from routers.auth import router as auth_router
from routers.reservations import router as reservations_router
from models.device_token import DeviceToken  
from routers.notifications import router as notifications_router  


app = FastAPI(
    title="Rescate API",
    description="Backend de la aplicación Rescate",
    version="1.0.0",
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


Base.metadata.create_all(bind=engine)


app.include_router(categories_router)
app.include_router(packs_router)
app.include_router(businesses_router)
app.include_router(auth_router)
app.include_router(reservations_router)
app.include_router(notifications_router)


@app.get("/")
def root():
    return {
        "message": "Rescate API funcionando",
        "status": "ok",
    }


@app.get("/api/health")
def health():
    try:
        with engine.connect():
            return {
                "status": "healthy",
                "database": "connected",
            }

    except Exception as error:
        return {
            "status": "error",
            "database": "disconnected",
            "detail": str(error),
        }