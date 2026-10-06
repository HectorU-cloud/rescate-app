"""Fixtures de las pruebas.

IMPORTANTE: las pruebas BORRAN y recrean las tablas. Por eso solo corren
contra una base de datos exclusiva para pruebas, indicada en
TEST_DATABASE_URL (y cuyo nombre debe contener "test"). Nunca usan la
DATABASE_URL de tu .env.

    createdb rescate_test
    export TEST_DATABASE_URL=postgresql://usuario:clave@localhost:5432/rescate_test
    pytest
"""
import os
import secrets
from datetime import datetime, timedelta, timezone

import pytest

TEST_DB_URL = os.getenv("TEST_DATABASE_URL")

if not TEST_DB_URL:
    pytest.skip(
        "Define TEST_DATABASE_URL (una base de datos SOLO para pruebas).",
        allow_module_level=True,
    )

db_name = TEST_DB_URL.rsplit("/", 1)[-1].split("?")[0].lower()

if "test" not in db_name:
    raise RuntimeError(
        f"Por seguridad, la base de pruebas debe tener 'test' en el nombre "
        f"(recibí '{db_name}')."
    )

# Debe fijarse ANTES de importar la app: database.py crea el motor al importarse.
os.environ["DATABASE_URL"] = TEST_DB_URL
os.environ.setdefault("SECRET_KEY", secrets.token_urlsafe(48))

from fastapi.testclient import TestClient  # noqa: E402

from database import Base, SessionLocal, engine  # noqa: E402
from main import app  # noqa: E402
from rate_limit import reset_all  # noqa: E402
from models.category import Category  # noqa: E402
from models.food_pack import FoodPack  # noqa: E402
from models.reservation import Reservation  # noqa: E402


@pytest.fixture(autouse=True)
def clean_db():
    """Cada prueba empieza con la base vacia y una categoria."""
    reset_all()  # los limitadores viven en memoria: empezar de cero

    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)

    with SessionLocal() as db:
        db.add(Category(name="Panadería", icon="bakery_dining"))
        db.commit()

    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def new_client() -> TestClient:
    return TestClient(app)


class Api:
    """Ayudas para armar escenarios sin repetir codigo en cada prueba."""

    def __init__(self, client: TestClient):
        self.c = client
        self._n = 0

    def register(self, is_business: bool = False) -> dict:
        self._n += 1
        r = self.c.post(
            "/api/auth/register",
            json={
                "name": f"Usuario {self._n}",
                "email": f"user{self._n}@test.com",
                "password": "secret123",
                "is_business": is_business,
            },
        )
        assert r.status_code in (200, 201), r.text
        data = r.json()
        return {
            "id": data["user_id"],
            "headers": {"Authorization": f"Bearer {data['access_token']}"},
        }

    def business(self) -> dict:
        owner = self.register(is_business=True)
        r = self.c.post(
            "/api/businesses",
            headers=owner["headers"],
            json={"name": "Panadería Test", "address": "Calle 1", "city": "Guayaquil"},
        )
        assert r.status_code == 201, r.text
        return owner

    def pack(self, owner: dict, quantity: int = 2, starts_in_h: float = -1, ends_in_h: float = 3) -> int:
        now = datetime.now(timezone.utc)
        r = self.c.post(
            "/api/packs",
            headers=owner["headers"],
            json={
                "category_id": 1,
                "title": "Pack sorpresa",
                "description": "Pan del día",
                "price": 2.0,
                "original_price": 6.0,
                "quantity": quantity,
                "pickup_start": (now + timedelta(hours=starts_in_h)).isoformat(),
                "pickup_end": (now + timedelta(hours=ends_in_h)).isoformat(),
            },
        )
        assert r.status_code == 201, r.text
        return r.json()["id"]

    def reserve(self, customer: dict, pack_id: int, quantity: int = 1, client: TestClient | None = None):
        return (client or self.c).post(
            "/api/reservations",
            headers=customer["headers"],
            json={"food_pack_id": pack_id, "quantity": quantity, "payment_method": "cash"},
        )

    def pack_quantity(self, pack_id: int) -> int:
        return self.c.get(f"/api/packs/{pack_id}").json()["quantity"]


@pytest.fixture
def api(client):
    return Api(client)


def move_pack_window(pack_id: int, ended_minutes_ago: int) -> None:
    """Simula que paso el tiempo: el horario de retiro termino hace N minutos."""
    end = datetime.utcnow() - timedelta(minutes=ended_minutes_ago)

    with SessionLocal() as db:
        pack = db.get(FoodPack, pack_id)
        pack.pickup_start = end - timedelta(hours=3)
        pack.pickup_end = end
        db.commit()


def reservation_status(reservation_id: int) -> str:
    with SessionLocal() as db:
        return db.get(Reservation, reservation_id).status
