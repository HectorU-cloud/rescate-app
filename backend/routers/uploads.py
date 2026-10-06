import io
import logging
import os
import secrets
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from database import get_db
from models.business import Business
from models.user import User
from security import get_current_user


logger = logging.getLogger("rescate.uploads")

router = APIRouter(
    prefix="/api/uploads",
    tags=["Uploads"],
)

# En produccion apunta a un volumen persistente: UPLOADS_DIR=/data/uploads
UPLOADS_DIR = Path(
    os.getenv("UPLOADS_DIR")
    or Path(__file__).resolve().parent.parent / "uploads"
)
PACKS_DIR = UPLOADS_DIR / "packs"
PACKS_URL_PREFIX = "/uploads/packs/"

MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # lo que aceptamos recibir
MAX_SIDE_PX = 1280                  # lado mayor de la imagen guardada
MAX_INPUT_PIXELS = 40_000_000       # evita "bombas de descompresion"

Image.MAX_IMAGE_PIXELS = MAX_INPUT_PIXELS


def ensure_upload_dirs() -> None:
    PACKS_DIR.mkdir(parents=True, exist_ok=True)


def is_valid_pack_image_url(value: str | None) -> bool:
    """Solo se aceptan imagenes subidas por esta API (o ninguna)."""
    if value is None:
        return True
    name = value.removeprefix(PACKS_URL_PREFIX)
    return (
        value.startswith(PACKS_URL_PREFIX)
        and name.endswith(".jpg")
        and "/" not in name
        and ".." not in name
        and len(name) <= 64
    )


def delete_pack_image_file(image_url: str | None) -> None:
    """Borra del disco la foto de un pack (si existe y es una ruta valida)."""
    if not image_url or not is_valid_pack_image_url(image_url):
        return

    try:
        (PACKS_DIR / image_url.removeprefix(PACKS_URL_PREFIX)).unlink(
            missing_ok=True
        )
    except OSError:
        pass


@router.post("/pack-image")
async def upload_pack_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sube la foto de un pack. Solo negocios registrados."""
    business = (
        db.query(Business)
        .filter(Business.owner_id == current_user.id)
        .first()
    )

    if not business:
        raise HTTPException(
            status_code=403,
            detail="Solo los negocios pueden subir fotos",
        )

    raw = await file.read(MAX_UPLOAD_BYTES + 1)

    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail="La foto es demasiado grande (máximo 8 MB)",
        )

    try:
        # Se valida el contenido real, no el nombre ni el content-type.
        with Image.open(io.BytesIO(raw)) as img:
            if img.format not in ("JPEG", "PNG", "WEBP"):
                raise ValueError("formato no permitido")

            img = ImageOps.exif_transpose(img)
            img = img.convert("RGB")
            img.thumbnail((MAX_SIDE_PX, MAX_SIDE_PX))
    except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            status_code=400,
            detail="El archivo no es una imagen válida (usa JPG, PNG o WEBP)",
        )

    # Se vuelve a codificar: quita metadatos EXIF (por ejemplo, la ubicacion
    # GPS de la foto) y deja un archivo liviano.
    filename = f"{secrets.token_hex(16)}.jpg"

    try:
        ensure_upload_dirs()
        img.save(
            PACKS_DIR / filename,
            format="JPEG",
            quality=82,
            optimize=True,
        )
    except OSError:
        # Carpeta sin permisos, disco lleno, volumen sin montar...
        logger.exception("No se pudo guardar la foto en %s", PACKS_DIR)
        raise HTTPException(
            status_code=500,
            detail="No pudimos guardar la foto. Inténtalo más tarde.",
        )

    return {"image_url": f"{PACKS_URL_PREFIX}{filename}"}
