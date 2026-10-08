"""Inicio de sesion con Google, eliminacion de cuenta, sesiones y pago online."""
import time

import pytest
from fastapi import HTTPException

import firebase_service
from database import SessionLocal
from models.user import User
from security import create_access_token


def claims(uid="fb-uid-1", email="ana@gmail.com", name="Ana G", verified=True, auth_age=0):
    return {
        "uid": uid,
        "email": email,
        "name": name,
        "email_verified": verified,
        "auth_time": time.time() - auth_age,
    }


@pytest.fixture
def google(monkeypatch):
    """Simula a Firebase: `state["claims"]` es lo que 'dice' el token."""
    state = {"claims": claims(), "deleted": [], "delete_error": None}

    def fake_verify(token):
        if isinstance(state["claims"], Exception):
            raise state["claims"]
        return state["claims"]

    def fake_delete(uid):
        if state["delete_error"]:
            raise state["delete_error"]
        state["deleted"].append(uid)

    monkeypatch.setattr("routers.auth.verify_id_token", fake_verify)
    monkeypatch.setattr("routers.auth.delete_firebase_user", fake_delete)
    return state


def _g(api, is_business=None, token="x"):
    body = {"id_token": token}
    if is_business is not None:
        body["is_business"] = is_business
    return api.c.post("/api/auth/google", json=body)


def _h(resp):
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


def _user(email):
    with SessionLocal() as db:
        return db.query(User).filter_by(email=email).first()


# ---------- crear cuenta y rol ----------

def test_cuenta_nueva_sin_rol_pide_elegirlo_y_no_crea_nada(api, google):
    r = _g(api)
    assert r.status_code == 409
    assert r.json()["detail"] == "ROLE_REQUIRED"
    assert _user("ana@gmail.com") is None


def test_cuenta_nueva_de_cliente(api, google):
    r = _g(api, is_business=False)
    assert r.status_code == 200, r.text
    assert r.json()["is_business"] is False

    user = _user("ana@gmail.com")
    assert user.firebase_uid == "fb-uid-1" and user.auth_provider == "google"


def test_cuenta_nueva_de_negocio_puede_crear_su_negocio(api, google):
    r = _g(api, is_business=True)
    assert r.status_code == 200 and r.json()["is_business"] is True

    created = api.c.post(
        "/api/businesses",
        headers=_h(r),
        json={"name": "Café Ana", "address": "Calle 1", "city": "Guayaquil"},
    )
    assert created.status_code == 201, created.text


def test_un_cliente_no_puede_volverse_negocio_pidiendolo_al_entrar(api, google):
    first = _g(api, is_business=False)
    again = _g(api, is_business=True)  # intento de escalar el rol

    assert again.status_code == 200
    assert again.json()["user_id"] == first.json()["user_id"]
    assert again.json()["is_business"] is False


def test_entrar_de_nuevo_no_cambia_el_nombre_elegido(api, google):
    _g(api, is_business=False)
    with SessionLocal() as db:
        db.query(User).filter_by(email="ana@gmail.com").update({"name": "Ana Personalizada"})
        db.commit()

    google["claims"] = claims(name="Otro Nombre De Google")
    assert _g(api).json()["name"] == "Ana Personalizada"


# ---------- tokens invalidos ----------

def test_correo_sin_verificar_se_rechaza(api, google):
    google["claims"] = claims(verified=False)
    assert _g(api, is_business=False).status_code == 401


def test_sin_correo_se_rechaza(api, google):
    google["claims"] = claims(email="")
    assert _g(api, is_business=False).status_code == 401


def test_token_invalido_se_rechaza_y_tras_muchos_intentos_se_bloquea(api, google):
    google["claims"] = HTTPException(401, "No se pudo validar la cuenta de Google.")

    codes = [_g(api, is_business=False).status_code for _ in range(25)]

    assert codes[0] == 401
    assert codes[-1] == 429


def test_un_fallo_de_firebase_no_cuenta_como_ataque(api, google):
    google["claims"] = HTTPException(503, "Firebase no responde")

    codes = {_g(api, is_business=False).status_code for _ in range(25)}
    assert codes == {503}


def test_usuario_desactivado_no_entra(api, google):
    _g(api, is_business=False)
    with SessionLocal() as db:
        db.query(User).filter_by(email="ana@gmail.com").update({"is_active": False})
        db.commit()

    assert _g(api).status_code == 403


# ---------- vincular con una cuenta existente ----------

def test_vincular_cuenta_existente_anula_la_clave_y_las_sesiones_previas(api, google):
    """El atacante registro el correo de Ana antes que ella."""
    r = api.c.post(
        "/api/auth/register",
        json={"name": "Atacante", "email": "ana@gmail.com", "password": "clave-atacante"},
    )
    attacker_headers = _h(r)
    assert api.c.get("/api/auth/me", headers=attacker_headers).status_code == 200

    ana = _g(api)  # Ana entra con Google: se vincula (cuenta ya existente)
    assert ana.status_code == 200
    assert ana.json()["user_id"] == r.json()["user_id"]

    # El atacante ya no puede entrar ni con su clave ni con su sesion vieja
    login = api.c.post("/api/auth/login", json={"email": "ana@gmail.com", "password": "clave-atacante"})
    assert login.status_code == 401
    assert api.c.get("/api/auth/me", headers=attacker_headers).status_code == 401

    # Ana sigue entrando
    assert api.c.get("/api/auth/me", headers=_h(ana)).status_code == 200


def test_entrar_otra_vez_con_google_no_cierra_la_sesion_anterior(api, google):
    first = _g(api, is_business=False)
    _g(api)  # segundo inicio con la misma identidad

    assert api.c.get("/api/auth/me", headers=_h(first)).status_code == 200


def test_la_dueña_recupera_una_clave_propia_con_el_correo(api, google, monkeypatch):
    api.c.post("/api/auth/register", json={"name": "X", "email": "ana@gmail.com", "password": "clave-atacante"})
    _g(api)

    sent = []
    monkeypatch.setattr("routers.auth.send_password_reset_code", lambda to, name, code, m: sent.append(code) or True)
    api.c.post("/api/auth/forgot-password", json={"email": "ana@gmail.com"})
    r = api.c.post(
        "/api/auth/reset-password",
        json={"email": "ana@gmail.com", "code": sent[0], "new_password": "clave-de-ana"},
    )
    assert r.status_code == 200

    login = api.c.post("/api/auth/login", json={"email": "ana@gmail.com", "password": "clave-de-ana"})
    assert login.status_code == 200


# ---------- cerrar sesiones ----------

def test_cambiar_la_contrasena_cierra_las_sesiones_abiertas(api, monkeypatch):
    user = api.register()
    assert api.c.get("/api/auth/me", headers=user["headers"]).status_code == 200

    sent = []
    monkeypatch.setattr("routers.auth.send_password_reset_code", lambda to, name, code, m: sent.append(code) or True)
    api.c.post("/api/auth/forgot-password", json={"email": "user1@test.com"})
    api.c.post(
        "/api/auth/reset-password",
        json={"email": "user1@test.com", "code": sent[0], "new_password": "nueva-clave"},
    )

    assert api.c.get("/api/auth/me", headers=user["headers"]).status_code == 401

    login = api.c.post("/api/auth/login", json={"email": "user1@test.com", "password": "nueva-clave"})
    assert api.c.get("/api/auth/me", headers=_h(login)).status_code == 200


def test_las_sesiones_emitidas_antes_de_esta_version_siguen_valiendo(api):
    """Tokens viejos (sin 'ver') deben funcionar mientras la version sea 0."""
    user = api.register()
    old_style = create_access_token({"sub": str(user["id"])})

    r = api.c.get("/api/auth/me", headers={"Authorization": f"Bearer {old_style}"})
    assert r.status_code == 200


# ---------- eliminar cuenta de Google ----------

def test_usuario_de_google_elimina_su_cuenta_y_se_borra_de_firebase(api, google):
    r = _g(api, is_business=False)

    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={"id_token": "fresco"})
    assert d.status_code == 200, d.text

    assert google["deleted"] == ["fb-uid-1"]
    user = api.c.get("/api/auth/me", headers=_h(r))
    assert user.status_code in (401, 403)

    with SessionLocal() as db:
        row = db.get(User, r.json()["user_id"])
        assert row.firebase_uid is None
        assert row.is_active is False
        assert "ana@gmail.com" not in row.email


def test_quien_elimino_su_cuenta_puede_volver_a_registrarse_con_google(api, google):
    first = _g(api, is_business=False)
    api.c.post("/api/auth/delete-account", headers=_h(first), json={"id_token": "fresco"})

    again = _g(api, is_business=False)
    assert again.status_code == 200, again.text
    assert again.json()["user_id"] != first.json()["user_id"]


def test_eliminar_exige_una_confirmacion_reciente_de_google(api, google):
    r = _g(api, is_business=False)
    google["claims"] = claims(auth_age=600)  # el inicio fue hace 10 min

    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={"id_token": "viejo"})
    assert d.status_code == 400
    assert google["deleted"] == []
    assert api.c.get("/api/auth/me", headers=_h(r)).status_code == 200


def test_eliminar_con_la_cuenta_de_google_de_otra_persona_falla(api, google):
    r = _g(api, is_business=False)
    google["claims"] = claims(uid="otro-uid", email="otra@gmail.com")

    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={"id_token": "x"})
    assert d.status_code == 400
    assert google["deleted"] == []


def test_eliminar_sin_ninguna_confirmacion_falla(api, google):
    r = _g(api, is_business=False)
    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={})
    assert d.status_code == 400


def test_token_de_google_en_cuenta_sin_google_falla(api, google):
    user = api.register()
    d = api.c.post("/api/auth/delete-account", headers=user["headers"], json={"id_token": "x"})
    assert d.status_code == 400


def test_si_firebase_falla_la_cuenta_no_se_elimina(api, google):
    r = _g(api, is_business=False)
    google["delete_error"] = HTTPException(503, "Firebase caido")

    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={"id_token": "fresco"})
    assert d.status_code == 503

    row = _user("ana@gmail.com")
    assert row.is_active is True and row.firebase_uid == "fb-uid-1"
    assert api.c.get("/api/auth/me", headers=_h(r)).status_code == 200


def test_las_reservas_pendientes_bloquean_antes_de_tocar_firebase(api, google):
    owner = api.business()
    r = _g(api, is_business=False)
    customer = {"headers": _h(r)}
    assert api.reserve(customer, api.pack(owner)).status_code == 201

    d = api.c.post("/api/auth/delete-account", headers=_h(r), json={"id_token": "fresco"})
    assert d.status_code == 400
    assert google["deleted"] == []


def test_cuenta_con_contrasena_no_toca_firebase(api, google):
    user = api.register()
    d = api.c.post("/api/auth/delete-account", headers=user["headers"], json={"password": "secret123"})
    assert d.status_code == 200
    assert google["deleted"] == []


# ---------- firebase_service ----------

def test_verify_id_token_traduce_los_errores(monkeypatch):
    monkeypatch.setattr(firebase_service, "_get_app", lambda: None)

    def invalido(token):
        raise firebase_service.auth.InvalidIdTokenError("malo")

    monkeypatch.setattr(firebase_service.auth, "verify_id_token", invalido)
    with pytest.raises(HTTPException) as e:
        firebase_service.verify_id_token("x")
    assert e.value.status_code == 401

    def caido(token):
        raise ConnectionError("sin red")

    monkeypatch.setattr(firebase_service.auth, "verify_id_token", caido)
    with pytest.raises(HTTPException) as e:
        firebase_service.verify_id_token("x")
    assert e.value.status_code == 503  # no se disfraza de "token invalido"


def test_delete_firebase_user(monkeypatch):
    monkeypatch.setattr(firebase_service, "_get_app", lambda: None)

    def no_existe(uid):
        raise firebase_service.auth.UserNotFoundError("ya no existe")

    monkeypatch.setattr(firebase_service.auth, "delete_user", no_existe)
    assert firebase_service.delete_firebase_user("u") is None  # ya borrado: ok

    def falla(uid):
        raise RuntimeError("boom")

    monkeypatch.setattr(firebase_service.auth, "delete_user", falla)
    with pytest.raises(HTTPException) as e:
        firebase_service.delete_firebase_user("u")
    assert e.value.status_code == 503


# ---------- pago online ----------

def test_el_pago_online_se_rechaza_hasta_que_exista_cobro_real(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner)

    r = api.c.post(
        "/api/reservations",
        headers=customer["headers"],
        json={"food_pack_id": pack_id, "quantity": 1, "payment_method": "online"},
    )
    assert r.status_code == 400
    assert "efectivo" in r.json()["detail"]
    assert api.pack_quantity(pack_id) == 2  # no se descontó stock


def test_sin_indicar_metodo_de_pago_es_efectivo(api):
    owner = api.business()
    customer = api.register()
    r = api.c.post(
        "/api/reservations",
        headers=customer["headers"],
        json={"food_pack_id": api.pack(owner), "quantity": 1},
    )
    assert r.status_code == 201
    assert r.json()["payment_method"] == "cash"
    assert r.json()["amount_to_collect"] > 0
