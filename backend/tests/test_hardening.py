"""Medidas para produccion: limites de intentos, health, CORS y Firebase."""
import json

import pytest
from fastapi.testclient import TestClient

import firebase_service
from main import app, engine


def _login(api, password, email="user1@test.com"):
    return api.c.post("/api/auth/login", json={"email": email, "password": password})


def test_cinco_fallos_bloquean_el_login_aunque_luego_la_clave_sea_buena(api):
    api.register()

    for _ in range(5):
        assert _login(api, "mala").status_code == 401

    r = _login(api, "secret123")  # clave correcta, pero ya esta bloqueado
    assert r.status_code == 429
    assert "intentos" in r.json()["detail"].lower()


def test_un_login_correcto_reinicia_el_contador(api):
    api.register()

    for _ in range(4):
        _login(api, "mala")

    assert _login(api, "secret123").status_code == 200

    for _ in range(4):  # otra vez 4 fallos: aun no bloquea
        assert _login(api, "mala").status_code == 401
    assert _login(api, "secret123").status_code == 200


def test_el_bloqueo_de_una_cuenta_no_afecta_a_otra_cuenta(api):
    api.register()  # user1
    api.register()  # user2

    for _ in range(5):
        _login(api, "mala", email="user1@test.com")

    assert _login(api, "secret123", email="user1@test.com").status_code == 429
    assert _login(api, "secret123", email="user2@test.com").status_code == 200


def test_correos_inexistentes_tambien_cuentan(api):
    for _ in range(5):
        assert _login(api, "x", email="nadie@test.com").status_code == 401
    assert _login(api, "x", email="nadie@test.com").status_code == 429


def test_limite_por_ip_al_pedir_codigos_de_recuperacion(api, monkeypatch):
    sent = []
    monkeypatch.setattr(
        "routers.auth.send_password_reset_code",
        lambda to, name, code, minutes: sent.append(to) or True,
    )

    for i in range(10):
        api.register()
    for i in range(1, 11):
        r = api.c.post("/api/auth/forgot-password", json={"email": f"user{i}@test.com"})
        assert r.status_code == 200
    assert len(sent) == 10

    # El numero 11 desde la misma IP: misma respuesta, pero no se envia nada
    r = api.c.post("/api/auth/forgot-password", json={"email": "user1@test.com"})
    assert r.status_code == 200
    assert len(sent) == 10


def test_health_ok(api):
    r = api.c.get("/api/health")
    assert r.status_code == 200
    assert r.json() == {"status": "healthy", "database": "connected"}


def test_health_no_filtra_detalles_y_responde_503(api, monkeypatch):
    def boom():
        raise RuntimeError("password=SECRETO host=10.0.0.5")

    monkeypatch.setattr("main.engine.connect", boom, raising=False)

    r = api.c.get("/api/health")
    assert r.status_code == 503
    assert "SECRETO" not in r.text and "10.0.0.5" not in r.text
    assert r.json()["status"] == "error"


def test_sin_cors_configurado_no_se_permite_ningun_origen(api):
    r = api.c.get("/api/health", headers={"Origin": "https://sitio-malicioso.com"})
    assert "access-control-allow-origin" not in r.headers


def test_firebase_acepta_credenciales_en_json_y_en_base64(monkeypatch):
    import base64

    seen = []
    monkeypatch.setattr(
        firebase_service.credentials,
        "Certificate",
        lambda arg: seen.append(arg) or "credencial",
    )

    data = {"type": "service_account", "project_id": "demo"}

    monkeypatch.setenv("FIREBASE_CREDENTIALS_JSON", json.dumps(data))
    assert firebase_service._load_credentials() == "credencial"

    monkeypatch.setenv(
        "FIREBASE_CREDENTIALS_JSON",
        base64.b64encode(json.dumps(data).encode()).decode(),
    )
    assert firebase_service._load_credentials() == "credencial"

    assert seen == [data, data]


def test_firebase_sin_credenciales_da_error_claro(monkeypatch, tmp_path):
    monkeypatch.delenv("FIREBASE_CREDENTIALS_JSON", raising=False)
    monkeypatch.setattr(firebase_service, "SERVICE_ACCOUNT_PATH", str(tmp_path / "no-existe.json"))

    with pytest.raises(Exception) as error:
        firebase_service._load_credentials()
    assert "Firebase" in str(error.value)


def test_database_url_acepta_postgres_a_secas():
    from database import normalize_database_url

    assert normalize_database_url("postgres://u:p@h:5432/db") == "postgresql://u:p@h:5432/db"
    assert normalize_database_url("postgresql://u:p@h/db") == "postgresql://u:p@h/db"
    assert normalize_database_url(None) is None


def test_seed_solo_categorias_no_crea_usuarios(api):
    from database import SessionLocal
    from models.category import Category
    from models.user import User
    from seed import seed

    seed(solo_categorias=True)

    with SessionLocal() as db:
        assert db.query(Category).count() >= 5
        assert db.query(User).count() == 0
