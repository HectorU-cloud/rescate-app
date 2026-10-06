import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

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
from models.password_reset import PasswordReset  # noqa: F401
from routers.notifications import router as notifications_router  
from routers.uploads import router as uploads_router, ensure_upload_dirs, UPLOADS_DIR
from routers.legal import router as legal_router


app = FastAPI(
    title="Rescate API",
    description="Backend de la aplicación Rescate",
    version="1.0.0",
)


# CORS solo importa para navegadores; la app movil no lo necesita.
# Si algun dia hay un sitio web, lista sus dominios separados por comas:
#   CORS_ORIGINS=https://miweb.com,https://www.miweb.com
_cors_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "").split(",")
    if origin.strip()
]

if _cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_cors_origins,
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
app.include_router(uploads_router)
app.include_router(legal_router)

# Fotos de los packs (se sirven en /uploads/packs/<archivo>.jpg)
ensure_upload_dirs()
app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")


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

    except Exception:
        # El detalle del error va al registro del servidor, no a quien consulta.
        logging.getLogger("rescate").exception("Fallo la conexion a la base de datos")

        # 503 para que el hosting detecte que el servicio no esta sano.
        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "database": "disconnected",
            },
        )