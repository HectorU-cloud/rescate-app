from datetime import datetime, timedelta, timezone

import os
import secrets
import sys

from passlib.context import CryptContext

from database import SessionLocal
from models.user import User
from models.category import Category
from models.business import Business
from models.food_pack import FoodPack


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def seed(solo_categorias: bool = False):
    db = SessionLocal()
    demo_password = os.getenv("SEED_DEMO_PASSWORD") or secrets.token_urlsafe(9)
    demo_hash = pwd_context.hash(demo_password)

    try:
        print("🌱 Iniciando seed de Rescate...")

        # -------------------------------------------------
        # CATEGORÍAS
        # -------------------------------------------------

        categories_data = [
            ("Panadería", "bakery"),
            ("Cafetería", "coffee"),
            ("Comida", "restaurant"),
            ("Pizza", "local_pizza"),
            ("Postres", "cake"),
        ]

        categories = {}

        for name, icon in categories_data:
            category = (
                db.query(Category)
                .filter(Category.name == name)
                .first()
            )

            if not category:
                category = Category(
                    name=name,
                    icon=icon,
                )
                db.add(category)
                db.flush()

            categories[name] = category

        print("✅ Categorías listas")

        # En produccion: python seed.py --solo-categorias (sin usuarios demo)
        if solo_categorias:
            db.commit()
            print("Listo: solo se crearon las categorías, sin datos demo.")
            return

        # -------------------------------------------------
        # USUARIOS DEMO
        # -------------------------------------------------

        users_data = [
            {
                "name": "Panadería La Tradición",
                "email": "panaderia.demo@rescate.ec",
            },
            {
                "name": "Café del Barrio",
                "email": "cafe.demo@rescate.ec",
            },
        ]

        users = {}

        for data in users_data:
            user = (
                db.query(User)
                .filter(User.email == data["email"])
                .first()
            )

            if not user:
                user = User(
                    name=data["name"],
                    email=data["email"],
                    password_hash=demo_hash,
                    is_business=True,
                    is_active=True,
                )
                db.add(user)
                db.flush()

            elif user.password_hash == "demo":
                user.password_hash = demo_hash
            users[data["email"]] = user

        print("✅ Usuarios demo listos")
        print(f"   Contraseña demo: {demo_password}")

        # -------------------------------------------------
        # NEGOCIOS
        # -------------------------------------------------

        businesses_data = [
            {
                "email": "panaderia.demo@rescate.ec",
                "name": "Panadería La Tradición",
                "description": "Panadería local con productos recién horneados.",
                "address": "Urdesa Central",
                "city": "Guayaquil",
                "latitude": -2.1709,
                "longitude": -79.9224,
                "phone": "0990000001",
            },
            {
                "email": "cafe.demo@rescate.ec",
                "name": "Café del Barrio",
                "description": "Cafetería local con productos preparados durante el día.",
                "address": "Kennedy",
                "city": "Guayaquil",
                "latitude": -2.1589,
                "longitude": -79.8991,
                "phone": "0990000002",
            },
        ]

        businesses = {}

        for data in businesses_data:
            owner = users[data["email"]]

            business = (
                db.query(Business)
                .filter(Business.owner_id == owner.id)
                .first()
            )

            if not business:
                business = Business(
                    owner_id=owner.id,
                    name=data["name"],
                    description=data["description"],
                    address=data["address"],
                    city=data["city"],
                    latitude=data["latitude"],
                    longitude=data["longitude"],
                    phone=data["phone"],
                )
                db.add(business)
                db.flush()

            businesses[data["name"]] = business

        print("✅ Negocios demo listos")

        # -------------------------------------------------
        # FOOD PACKS
        # -------------------------------------------------
        # ⚠️ AQUÍ ESTÁ EL CAMBIO CLAVE:
        # Usamos datetime.now(timezone.utc) para que coincida
        # con el filtro del endpoint /api/packs.

        now = datetime.now(timezone.utc)

        packs_data = [
            {
                "business": "Panadería La Tradición",
                "category": "Panadería",
                "title": "Pack sorpresa de panadería",
                "description": (
                    "Una selección sorpresa de panes, dulces "
                    "y productos recién horneados."
                ),
                "price": 3.50,
                "original_price": 8.00,
                "quantity": 4,
                "start": now + timedelta(hours=2),
                "end": now + timedelta(hours=6),
            },
            {
                "business": "Café del Barrio",
                "category": "Cafetería",
                "title": "Pack sorpresa de cafetería",
                "description": (
                    "Una selección sorpresa de productos "
                    "de cafetería preparados durante el día."
                ),
                "price": 4.00,
                "original_price": 9.50,
                "quantity": 2,
                "start": now + timedelta(hours=1, minutes=30),
                "end": now + timedelta(hours=5),
            },
            {
                "business": "Panadería La Tradición",
                "category": "Postres",
                "title": "Pack sorpresa de postres",
                "description": (
                    "Una selección sorpresa de postres "
                    "y productos dulces del día."
                ),
                "price": 3.00,
                "original_price": 7.00,
                "quantity": 5,
                "start": now + timedelta(hours=2),
                "end": now + timedelta(hours=8),
            },
        ]

        for data in packs_data:
            business = businesses[data["business"]]
            category = categories[data["category"]]

            existing_pack = (
                db.query(FoodPack)
                .filter(
                    FoodPack.business_id == business.id,
                    FoodPack.title == data["title"],
                )
                .first()
            )

            if not existing_pack:
                pack = FoodPack(
                    business_id=business.id,
                    category_id=category.id,
                    title=data["title"],
                    description=data["description"],
                    price=data["price"],
                    original_price=data["original_price"],
                    quantity=data["quantity"],
                    pickup_start=data["start"],
                    pickup_end=data["end"],
                    status="available",
                    image_url=None,
                )

                db.add(pack)

        db.commit()

        print("✅ Food Packs creados")
        print()
        print("🎉 Seed completado correctamente.")

    except Exception as error:
        db.rollback()
        print()
        print("❌ Error durante el seed:")
        print(error)
        raise

    finally:
        db.close()


if __name__ == "__main__":
    seed(solo_categorias="--solo-categorias" in sys.argv)