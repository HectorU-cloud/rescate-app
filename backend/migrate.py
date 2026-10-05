from sqlalchemy import text

from database import engine


def migrate():
    with engine.connect() as conn:
        print("🔄 Migrando tabla reservations...")

        conn.execute(text("""
            ALTER TABLE reservations
            ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20)
            DEFAULT 'online' NOT NULL
        """))
        print("✅ payment_method")

        conn.execute(text("""
            ALTER TABLE reservations
            ADD COLUMN IF NOT EXISTS service_fee NUMERIC(10, 2)
            DEFAULT 0 NOT NULL
        """))
        print("✅ service_fee")

        conn.execute(text("""
            ALTER TABLE reservations
            ADD COLUMN IF NOT EXISTS amount_to_collect NUMERIC(10, 2)
            DEFAULT 0 NOT NULL
        """))
        print("✅ amount_to_collect")

        conn.execute(text("""
            ALTER TABLE reservations
            ADD COLUMN IF NOT EXISTS fee_settled BOOLEAN
            DEFAULT FALSE NOT NULL
        """))
        print("✅ fee_settled")

        # 👇 NUEVA COLUMNA
        conn.execute(text("""
            ALTER TABLE reservations
            ADD COLUMN IF NOT EXISTS seen_by_business BOOLEAN
            DEFAULT FALSE NOT NULL
        """))
        print("✅ seen_by_business")

        # 👇 Tabla device_tokens
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS device_tokens (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                token VARCHAR(500) NOT NULL UNIQUE,
                platform VARCHAR(20) DEFAULT 'android',
                created_at TIMESTAMP DEFAULT NOW() NOT NULL
            )
        """))
        print("✅ tabla device_tokens")

        conn.commit()

        print()
        print("🎉 Migración completada")


if __name__ == "__main__":
    migrate()