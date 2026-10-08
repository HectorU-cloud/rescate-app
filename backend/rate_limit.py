"""Limitador de intentos en memoria (contra adivinar contrasenas y spam).

Vive en la memoria de cada proceso: si el servidor corre con varios
procesos (workers), cada uno cuenta por separado, asi que el limite real es
un poco mayor. Para los volumenes de este MVP alcanza; si crece, conviene
moverlo a Redis.
"""
import threading
import time
from collections import deque


class AttemptLimiter:
    def __init__(self, max_attempts: int, window_seconds: int):
        self.max_attempts = max_attempts
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def _prune(self, key: str, now: float) -> deque[float]:
        hits = self._hits.setdefault(key, deque())
        while hits and now - hits[0] > self.window:
            hits.popleft()
        return hits

    def is_blocked(self, key: str) -> bool:
        with self._lock:
            now = time.monotonic()
            hits = self._prune(key, now)
            blocked = len(hits) >= self.max_attempts
            if not hits:
                self._hits.pop(key, None)
            return blocked

    def hit(self, key: str) -> None:
        with self._lock:
            now = time.monotonic()
            self._prune(key, now).append(now)

            # Limpieza ocasional para que el diccionario no crezca sin fin
            if len(self._hits) > 20_000:
                for k in list(self._hits):
                    if not self._prune(k, now):
                        self._hits.pop(k, None)

    def reset(self, key: str) -> None:
        with self._lock:
            self._hits.pop(key, None)

    def clear(self) -> None:
        with self._lock:
            self._hits.clear()


# Intentos fallidos de login: por (correo + IP) y por IP en general.
login_by_account = AttemptLimiter(max_attempts=5, window_seconds=15 * 60)
login_by_ip = AttemptLimiter(max_attempts=30, window_seconds=15 * 60)

# Tokens de Google invalidos por IP.
google_fail_by_ip = AttemptLimiter(max_attempts=20, window_seconds=15 * 60)

# Solicitudes de codigo de recuperacion por IP (evita llenar buzones ajenos).
forgot_by_ip = AttemptLimiter(max_attempts=10, window_seconds=60 * 60)


def client_ip(request) -> str:
    return request.client.host if request.client else "desconocida"


def reset_all() -> None:
    """Para las pruebas."""
    for limiter in (login_by_account, login_by_ip, forgot_by_ip, google_fail_by_ip):
        limiter.clear()
