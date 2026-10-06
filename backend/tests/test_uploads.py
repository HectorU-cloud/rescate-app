"""Fotos de los packs."""
import io

import pytest
from PIL import Image

import routers.uploads as uploads


@pytest.fixture(autouse=True)
def carpeta_temporal(tmp_path, monkeypatch):
    """Las fotos de las pruebas van a una carpeta temporal, no al proyecto."""
    monkeypatch.setattr(uploads, "PACKS_DIR", tmp_path / "packs")
    return tmp_path / "packs"


def _imagen(fmt="JPEG", size=(100, 100), con_exif=False) -> bytes:
    buf = io.BytesIO()
    kwargs = {}
    if con_exif and fmt == "JPEG":
        exif = Image.Exif()
        exif[0x010F] = "CamaraDePrueba"
        exif[0x8825] = {1: "S", 2: (2.0, 10.0, 0.0), 3: "W", 4: (79.0, 54.0, 0.0)}  # GPS
        kwargs["exif"] = exif
    Image.new("RGB", size, (200, 120, 50)).save(buf, fmt, **kwargs)
    return buf.getvalue()


def _subir(api, user, data, nombre="foto.jpg", tipo="image/jpeg"):
    return api.c.post(
        "/api/uploads/pack-image",
        headers=user["headers"],
        files={"file": (nombre, data, tipo)},
    )


def test_el_negocio_sube_una_foto_reducida_y_sin_gps(api, carpeta_temporal):
    owner = api.business()

    r = _subir(api, owner, _imagen(size=(3000, 2000), con_exif=True))
    assert r.status_code == 200, r.text

    url = r.json()["image_url"]
    assert uploads.is_valid_pack_image_url(url)

    guardada = Image.open(carpeta_temporal / url.removeprefix("/uploads/packs/"))
    assert max(guardada.size) == 1280
    assert not guardada.getexif().get(0x8825)  # sin ubicacion GPS
    assert not guardada.getexif().get(0x010F)  # sin datos de la camara


@pytest.mark.parametrize("formato", ["PNG", "WEBP"])
def test_acepta_png_y_webp(api, formato):
    assert _subir(api, api.business(), _imagen(formato)).status_code == 200


def test_rechaza_formatos_no_permitidos(api):
    owner = api.business()
    assert _subir(api, owner, _imagen("GIF", (50, 50)), "a.gif", "image/gif").status_code == 400


def test_rechaza_un_script_disfrazado_de_jpg(api):
    r = _subir(api, api.business(), b"<?php echo 1; ?>", "malo.jpg")
    assert r.status_code == 400


def test_rechaza_archivos_de_mas_de_8mb(api):
    r = _subir(api, api.business(), b"\xff\xd8" + b"0" * (9 * 1024 * 1024))
    assert r.status_code == 413


def test_un_cliente_no_puede_subir_fotos(api):
    assert _subir(api, api.register(), _imagen()).status_code == 403


def test_sin_sesion_no_se_puede_subir(api):
    r = api.c.post("/api/uploads/pack-image", files={"file": ("a.jpg", _imagen(), "image/jpeg")})
    assert r.status_code in (401, 403)


def test_si_no_se_puede_escribir_el_error_es_claro(api, monkeypatch, tmp_path):
    # Una "carpeta" que en realidad es un archivo: no se puede crear dentro
    bloqueo = tmp_path / "archivo"
    bloqueo.write_text("x")
    monkeypatch.setattr(uploads, "PACKS_DIR", bloqueo / "packs")

    r = _subir(api, api.business(), _imagen())
    assert r.status_code == 500
    assert "guardar" in r.json()["detail"]  # no dice "imagen invalida"


def test_el_pack_solo_acepta_fotos_subidas_por_la_api(api):
    owner = api.business()
    base = {
        "category_id": 1, "title": "x", "description": "x", "price": 2,
        "original_price": 6, "quantity": 1,
        "pickup_start": "2030-01-01T10:00:00+00:00",
        "pickup_end": "2030-01-01T12:00:00+00:00",
    }
    for malo in [
        "http://evil.com/x.jpg",
        "/uploads/packs/../../main.py",
        "/uploads/packs/a/b.jpg",
        "javascript:alert(1)",
        "/uploads/packs/x.php",
    ]:
        r = api.c.post("/api/packs", headers=owner["headers"], json={**base, "image_url": malo})
        assert r.status_code == 422, malo


def test_la_foto_queda_en_el_pack_y_se_conserva_al_editar(api):
    owner = api.business()
    url = _subir(api, owner, _imagen()).json()["image_url"]
    pack_id = api.pack(owner)

    r = api.c.put(f"/api/packs/{pack_id}", headers=owner["headers"], json={"image_url": url})
    assert r.status_code == 200 and r.json()["image_url"] == url

    r = api.c.put(f"/api/packs/{pack_id}", headers=owner["headers"], json={"title": "Otro titulo"})
    assert r.json()["image_url"] == url  # editar otra cosa no borra la foto

    r = api.c.put(f"/api/packs/{pack_id}", headers=owner["headers"], json={"image_url": "http://evil.com/x.jpg"})
    assert r.status_code == 422
