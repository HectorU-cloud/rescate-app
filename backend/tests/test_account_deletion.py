"""Eliminar cuenta (requisito de Google Play y App Store)."""
from database import SessionLocal
from models.business import Business
from models.device_token import DeviceToken
from models.food_pack import FoodPack
from models.user import User
from tests.conftest import move_pack_window


def _delete(api, user, password="secret123"):
    return api.c.post(
        "/api/auth/delete-account",
        headers=user["headers"],
        json={"password": password},
    )


def test_contrasena_incorrecta_no_elimina(api):
    customer = api.register()

    r = _delete(api, customer, password="otra-clave")
    assert r.status_code == 400

    with SessionLocal() as db:
        assert db.get(User, customer["id"]).is_active is True


def test_cliente_elimina_su_cuenta_y_no_puede_volver_a_entrar(api):
    customer = api.register()
    email = "user1@test.com"

    with SessionLocal() as db:
        db.add(DeviceToken(user_id=customer["id"], token="abc123", platform="android"))
        db.commit()

    r = _delete(api, customer)
    assert r.status_code == 200, r.text

    with SessionLocal() as db:
        user = db.get(User, customer["id"])
        assert user.is_active is False
        assert user.name == "Usuario eliminado"
        assert email not in user.email
        assert db.query(DeviceToken).filter_by(user_id=customer["id"]).count() == 0

    # El token anterior ya no sirve y el login falla
    assert api.c.get("/api/reservations", headers=customer["headers"]).status_code in (401, 403)
    r = api.c.post("/api/auth/login", json={"email": email, "password": "secret123"})
    assert r.status_code in (400, 401, 403)

    # El correo queda libre para registrarse otra vez
    r = api.c.post(
        "/api/auth/register",
        json={"name": "Nuevo", "email": email, "password": "secret123"},
    )
    assert r.status_code == 201


def test_cliente_con_reserva_pendiente_no_puede_eliminar(api):
    owner = api.business()
    customer = api.register()
    api.reserve(customer, api.pack(owner))

    r = _delete(api, customer)
    assert r.status_code == 400
    assert "pendiente" in r.json()["detail"]


def test_cliente_con_historial_conserva_reservas_anonimas(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner)
    res = api.reserve(customer, pack_id).json()

    api.c.post(
        f"/api/reservations/{res['reservation_code']}/validate",
        headers=owner["headers"],
    )

    assert _delete(api, customer).status_code == 200

    received = api.c.get("/api/reservations/received", headers=owner["headers"]).json()
    assert len(received) == 1
    assert received[0]["customer_name"] == "Usuario eliminado"


def test_negocio_elimina_cuenta_y_se_limpian_sus_datos(api):
    owner = api.business()
    customer = api.register()
    pack_con_historial = api.pack(owner)
    pack_sin_historial = api.pack(owner)

    res = api.reserve(customer, pack_con_historial).json()
    api.c.post(
        f"/api/reservations/{res['reservation_code']}/validate",
        headers=owner["headers"],
    )

    assert _delete(api, owner).status_code == 200

    with SessionLocal() as db:
        biz = db.query(Business).filter_by(owner_id=owner["id"]).one()
        assert biz.name == "Negocio eliminado"
        assert biz.phone is None and biz.latitude is None

        assert db.get(FoodPack, pack_sin_historial) is None  # borrado
        kept = db.get(FoodPack, pack_con_historial)
        assert kept is not None and kept.status == "paused"  # oculto, historial intacto

    # Ya no aparece ningun pack publico
    assert api.c.get("/api/packs").json() == []


def test_negocio_con_reservas_pendientes_no_puede_eliminar(api):
    owner = api.business()
    customer = api.register()
    api.reserve(customer, api.pack(owner))

    r = _delete(api, owner)
    assert r.status_code == 400
    assert "pendiente" in r.json()["detail"]


def test_reserva_vencida_ya_no_bloquea_la_eliminacion(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner)
    api.reserve(customer, pack_id)
    move_pack_window(pack_id, ended_minutes_ago=120)  # vencio hace 2 horas

    assert _delete(api, customer).status_code == 200


def test_sin_sesion_no_se_puede_eliminar(api):
    r = api.c.post("/api/auth/delete-account", json={"password": "x"})
    assert r.status_code in (401, 403)


def test_paginas_legales_publicas_sin_sesion(api, monkeypatch):
    monkeypatch.setenv("SUPPORT_EMAIL", "soporte@miapp.ec")
    monkeypatch.setenv("COMPANY_NAME", "Mi Empresa S.A.")

    for path, texto in [
        ("/privacy", "Política de privacidad"),
        ("/terms", "Términos y condiciones"),
        ("/account-deletion", "Eliminar tu cuenta"),
    ]:
        r = api.c.get(path)
        assert r.status_code == 200, path
        assert texto in r.text
        assert "soporte@miapp.ec" in r.text

    assert "Mi Empresa S.A." in api.c.get("/privacy").text


def test_paginas_legales_avisan_si_falta_configuracion(api, monkeypatch):
    monkeypatch.delenv("SUPPORT_EMAIL", raising=False)
    assert "configura SUPPORT_EMAIL" in api.c.get("/privacy").text


def test_paginas_legales_escapan_html_del_env(api, monkeypatch):
    monkeypatch.setenv("COMPANY_NAME", "<script>alert(1)</script>")
    assert "<script>alert(1)</script>" not in api.c.get("/privacy").text
