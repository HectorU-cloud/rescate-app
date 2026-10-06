"""Flujo completo reservar -> retirar y sus casos limite."""
import threading

import pytest

from reservation_rules import NO_SHOW_LIMIT
from tests.conftest import move_pack_window, new_client, reservation_status


def test_flujo_completo_reservar_y_retirar(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner, quantity=2)

    r = api.reserve(customer, pack_id)
    assert r.status_code == 201, r.text
    res = r.json()
    assert res["status"] == "reserved"
    assert api.pack_quantity(pack_id) == 1  # se descuenta el stock

    r = api.c.post(
        f"/api/reservations/{res['reservation_code']}/validate",
        headers=owner["headers"],
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "picked_up"

    # No se puede validar dos veces
    r = api.c.post(
        f"/api/reservations/{res['reservation_code']}/validate",
        headers=owner["headers"],
    )
    assert r.status_code == 400


def test_otro_negocio_no_puede_validar(api):
    owner = api.business()
    other_owner = api.business()
    customer = api.register()
    code = api.reserve(customer, api.pack(owner)).json()["reservation_code"]

    r = api.c.post(
        f"/api/reservations/{code}/validate", headers=other_owner["headers"]
    )
    assert r.status_code == 403


def test_cancelar_devuelve_stock_una_sola_vez(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner, quantity=2)
    res = api.reserve(customer, pack_id).json()
    assert api.pack_quantity(pack_id) == 1

    url = f"/api/reservations/{res['id']}/cancel"
    assert api.c.patch(url, headers=customer["headers"]).status_code == 200
    assert api.pack_quantity(pack_id) == 2

    # Segundo intento: rechazado y el stock no sube de nuevo
    assert api.c.patch(url, headers=customer["headers"]).status_code == 400
    assert api.pack_quantity(pack_id) == 2


def test_nadie_mas_puede_cancelar_mi_reserva(api):
    owner = api.business()
    customer = api.register()
    stranger = api.register()
    res = api.reserve(customer, api.pack(owner)).json()

    r = api.c.patch(
        f"/api/reservations/{res['id']}/cancel", headers=stranger["headers"]
    )
    assert r.status_code == 403


def test_no_se_puede_reservar_mas_que_el_stock(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner, quantity=1)

    assert api.reserve(customer, pack_id, quantity=2).status_code == 400
    assert api.pack_quantity(pack_id) == 1


def test_no_se_puede_reservar_fuera_de_horario(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner, quantity=3)
    move_pack_window(pack_id, ended_minutes_ago=5)

    r = api.reserve(customer, pack_id)
    assert r.status_code == 400
    assert "horario" in r.json()["detail"].lower()
    assert api.pack_quantity(pack_id) == 3


def test_veinte_clientes_a_la_vez_por_el_ultimo_pack(api):
    """Regresion: antes se aceptaban varias reservas del mismo ultimo pack."""
    owner = api.business()
    pack_id = api.pack(owner, quantity=1)
    customers = [api.register() for _ in range(20)]

    barrier = threading.Barrier(len(customers))
    codes: list[int] = []

    def go(customer):
        client = new_client()  # un cliente HTTP por hilo
        barrier.wait()
        codes.append(api.reserve(customer, pack_id, client=client).status_code)

    threads = [threading.Thread(target=go, args=(c,)) for c in customers]
    [t.start() for t in threads]
    [t.join() for t in threads]

    assert codes.count(201) == 1, codes
    assert api.pack_quantity(pack_id) == 0


def test_doble_cancelacion_simultanea_no_duplica_stock(api):
    owner = api.business()
    customer = api.register()
    pack_id = api.pack(owner, quantity=2)
    res = api.reserve(customer, pack_id).json()  # stock 2 -> 1

    barrier = threading.Barrier(5)
    codes: list[int] = []

    def go():
        client = new_client()
        barrier.wait()
        codes.append(
            client.patch(
                f"/api/reservations/{res['id']}/cancel",
                headers=customer["headers"],
            ).status_code
        )

    threads = [threading.Thread(target=go) for _ in range(5)]
    [t.start() for t in threads]
    [t.join() for t in threads]

    assert codes.count(200) == 1, codes
    assert api.pack_quantity(pack_id) == 2  # y no 6
