"""Recuperar contrasena con codigo de 6 digitos."""
import threading
from datetime import datetime, timedelta

import httpx
import pytest

import email_service
from database import SessionLocal
from models.password_reset import PasswordReset
from tests.conftest import new_client

EMAIL = "user1@test.com"  # el primer usuario que crea api.register()


@pytest.fixture
def sent(monkeypatch):
    """Intercepta los correos: guarda (correo, codigo) en vez de enviarlos."""
    box: list[tuple[str, str]] = []

    def fake(to, name, code, minutes):
        box.append((to, code))
        return True

    monkeypatch.setattr("routers.auth.send_password_reset_code", fake)
    return box


def _forgot(api, email=EMAIL):
    return api.c.post("/api/auth/forgot-password", json={"email": email})


def _reset(api, code, password="nueva-clave", email=EMAIL):
    return api.c.post(
        "/api/auth/reset-password",
        json={"email": email, "code": code, "new_password": password},
    )


def _login(api, password, email=EMAIL):
    return api.c.post("/api/auth/login", json={"email": email, "password": password})


def test_flujo_completo(api, sent):
    api.register()

    assert _forgot(api).status_code == 200
    assert len(sent) == 1
    to, code = sent[0]
    assert to == EMAIL
    assert len(code) == 6 and code.isdigit()

    assert _reset(api, code).status_code == 200

    assert _login(api, "nueva-clave").status_code == 200
    assert _login(api, "secret123").status_code == 401  # la vieja ya no sirve


def test_correo_inexistente_responde_igual_y_no_envia(api, sent):
    api.register()
    real = _forgot(api)
    fake = _forgot(api, email="nadie@test.com")

    assert fake.status_code == 200
    assert fake.json() == real.json()  # no revela quien tiene cuenta
    assert [to for to, _ in sent] == [EMAIL]  # solo se envio al real


def test_cuenta_eliminada_no_recibe_codigo(api, sent):
    user = api.register()
    api.c.post("/api/auth/delete-account", headers=user["headers"], json={"password": "secret123"})

    assert _forgot(api).status_code == 200
    assert sent == []


def test_el_codigo_no_se_guarda_en_claro(api, sent):
    api.register()
    _forgot(api)
    code = sent[0][1]

    with SessionLocal() as db:
        reset = db.query(PasswordReset).one()
        assert reset.code_hash != code
        assert code not in reset.code_hash
        assert len(reset.code_hash) == 64


def test_codigo_incorrecto(api, sent):
    api.register()
    _forgot(api)
    wrong = "000000" if sent[0][1] != "000000" else "111111"

    r = _reset(api, wrong)
    assert r.status_code == 400
    assert _login(api, "secret123").status_code == 200  # nada cambio


def test_cinco_intentos_fallidos_bloquean_el_codigo_aunque_luego_sea_correcto(api, sent):
    api.register()
    _forgot(api)
    code = sent[0][1]
    wrong = "000000" if code != "000000" else "111111"

    for _ in range(5):
        assert _reset(api, wrong).status_code == 400

    assert _reset(api, code).status_code == 400  # ya esta bloqueado
    assert _login(api, "secret123").status_code == 200


def test_adivinar_en_paralelo_no_salta_el_limite(api, sent):
    api.register()
    _forgot(api)
    code = sent[0][1]
    wrong = "000000" if code != "000000" else "111111"

    barrier = threading.Barrier(20)
    results: list[int] = []

    def go():
        client = new_client()
        barrier.wait()
        results.append(
            client.post(
                "/api/auth/reset-password",
                json={"email": EMAIL, "code": wrong, "new_password": "x-nueva-1"},
            ).status_code
        )

    threads = [threading.Thread(target=go) for _ in range(20)]
    [t.start() for t in threads]
    [t.join() for t in threads]

    assert set(results) == {400}
    # Con el bloqueo de fila se cuentan EXACTAMENTE 5 intentos y el codigo
    # queda inutilizado. Sin el bloqueo se pierden conteos y quedan intentos
    # de sobra para adivinar.
    with SessionLocal() as db:
        reset = db.query(PasswordReset).one()
        assert reset.attempts == 5
        assert reset.used is True
    assert _reset(api, code).status_code == 400


def test_codigo_vencido(api, sent):
    api.register()
    _forgot(api)

    with SessionLocal() as db:
        reset = db.query(PasswordReset).one()
        reset.expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.commit()

    assert _reset(api, sent[0][1]).status_code == 400


def test_el_codigo_solo_sirve_una_vez(api, sent):
    api.register()
    _forgot(api)
    code = sent[0][1]

    assert _reset(api, code).status_code == 200
    assert _reset(api, code, password="otra-clave-2").status_code == 400
    assert _login(api, "nueva-clave").status_code == 200


def test_un_codigo_nuevo_invalida_el_anterior(api, sent):
    api.register()
    _forgot(api)
    _forgot(api)
    first, second = sent[0][1], sent[1][1]

    if first != second:
        assert _reset(api, first).status_code == 400
    assert _reset(api, second).status_code == 200


def test_limite_de_solicitudes_por_hora(api, sent):
    api.register()

    for _ in range(5):
        assert _forgot(api).status_code == 200  # siempre responde igual

    assert len(sent) == 3  # pero solo se enviaron 3 correos


def test_contrasena_corta_se_rechaza_sin_gastar_el_codigo(api, sent):
    api.register()
    _forgot(api)
    code = sent[0][1]

    assert _reset(api, code, password="123").status_code == 400
    assert _reset(api, code).status_code == 200  # el codigo seguia vigente


def test_codigo_de_otro_usuario_no_sirve(api, sent):
    api.register()  # user1
    api.register()  # user2
    _forgot(api, email="user1@test.com")
    code_user1 = sent[0][1]

    assert _reset(api, code_user1, email="user2@test.com").status_code == 400
    assert _login(api, "secret123", email="user2@test.com").status_code == 200


# ---------- envio por Resend ----------

class _Resp:
    def __init__(self, status, text="{}"):
        self.status_code = status
        self.text = text


def test_send_email_arma_bien_la_peticion_a_resend(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_clave_de_prueba")
    monkeypatch.setenv("FROM_EMAIL", "Rescate <rescate@vectoraec.app>")
    captured = {}

    def fake_post(url, headers, json, timeout):
        captured.update(url=url, headers=headers, json=json)
        return _Resp(200)

    monkeypatch.setattr(email_service.httpx, "post", fake_post)

    assert email_service.send_password_reset_code("ana@test.com", "Ana Pérez", "123456", 10) is True
    assert captured["url"] == "https://api.resend.com/emails"
    assert captured["headers"]["Authorization"] == "Bearer re_clave_de_prueba"
    body = captured["json"]
    assert body["from"] == "Rescate <rescate@vectoraec.app>"
    assert body["to"] == ["ana@test.com"]
    assert "123456" in body["subject"] and "123456" in body["text"] and "123456" in body["html"]
    assert "Hola Ana" in body["text"]


def test_send_email_sin_configuracion_no_llama_a_resend(monkeypatch):
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    monkeypatch.setattr(
        email_service.httpx, "post",
        lambda *a, **k: pytest.fail("no debia llamar a Resend"),
    )
    assert email_service.send_email("a@b.com", "x", "<p>x</p>", "x") is False


def test_send_email_no_lanza_si_resend_falla(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_x")
    monkeypatch.setenv("FROM_EMAIL", "a@b.com")

    monkeypatch.setattr(email_service.httpx, "post", lambda *a, **k: _Resp(403, "domain not verified"))
    assert email_service.send_email("a@b.com", "x", "<p>x</p>", "x") is False

    def boom(*a, **k):
        raise httpx.ConnectError("sin red")

    monkeypatch.setattr(email_service.httpx, "post", boom)
    assert email_service.send_email("a@b.com", "x", "<p>x</p>", "x") is False
