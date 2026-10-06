"""Reservas que nadie retira."""
from reservation_rules import NO_SHOW_GRACE_MINUTES, NO_SHOW_LIMIT
from tests.conftest import move_pack_window, reservation_status


def _reserve_and_expire(api, owner, customer, minutes_after_end):
    pack_id = api.pack(owner, quantity=5)
    res = api.reserve(customer, pack_id).json()
    move_pack_window(pack_id, ended_minutes_ago=minutes_after_end)
    return pack_id, res


def test_dentro_del_margen_de_gracia_sigue_reservada(api):
    owner = api.business()
    customer = api.register()
    _, res = _reserve_and_expire(api, owner, customer, minutes_after_end=1)

    api.c.get("/api/reservations", headers=customer["headers"])
    assert reservation_status(res["id"]) == "reserved"


def test_pasado_el_margen_se_marca_no_show_sin_devolver_stock(api):
    owner = api.business()
    customer = api.register()
    pack_id, res = _reserve_and_expire(
        api, owner, customer, minutes_after_end=NO_SHOW_GRACE_MINUTES + 5
    )
    stock_before = api.pack_quantity(pack_id)

    r = api.c.get("/api/reservations", headers=customer["headers"])
    assert r.status_code == 200
    assert reservation_status(res["id"]) == "no_show"
    assert api.pack_quantity(pack_id) == stock_before  # la comida ya no se vende


def test_el_negocio_no_puede_validar_una_reserva_vencida(api):
    owner = api.business()
    customer = api.register()
    _, res = _reserve_and_expire(
        api, owner, customer, minutes_after_end=NO_SHOW_GRACE_MINUTES + 5
    )

    r = api.c.post(
        f"/api/reservations/{res['reservation_code']}/validate",
        headers=owner["headers"],
    )
    assert r.status_code == 400
    assert "venci" in r.json()["detail"].lower()


def test_no_show_no_cuenta_como_ingreso_y_aparece_en_estadisticas(api):
    owner = api.business()
    customer = api.register()
    _reserve_and_expire(
        api, owner, customer, minutes_after_end=NO_SHOW_GRACE_MINUTES + 5
    )

    stats = api.c.get("/api/businesses/me/stats", headers=owner["headers"]).json()
    assert stats["no_show_reservations"] == 1
    assert stats["total_revenue"] == 0
    assert stats["pending_reservations"] == 0


def test_reservar_se_bloquea_tras_demasiados_no_retiros(api):
    if NO_SHOW_LIMIT <= 0:
        return  # bloqueo desactivado por configuracion

    owner = api.business()
    customer = api.register()

    for _ in range(NO_SHOW_LIMIT):
        _reserve_and_expire(
            api, owner, customer, minutes_after_end=NO_SHOW_GRACE_MINUTES + 5
        )

    r = api.reserve(customer, api.pack(owner))
    assert r.status_code == 403
    assert "sin retirar" in r.json()["detail"]

    # Otro cliente no se ve afectado
    other = api.register()
    assert api.reserve(other, api.pack(owner)).status_code == 201
