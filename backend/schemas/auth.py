from pydantic import BaseModel, EmailStr


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    is_business: bool = False


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class GoogleLoginRequest(BaseModel):
    id_token: str
    # Solo importa al crear la cuenta. Si falta y la cuenta es nueva,
    # el servidor responde 409 ROLE_REQUIRED para que la app pregunte.
    is_business: bool | None = None


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str


class DeleteAccountRequest(BaseModel):
    # Cuentas con contrasena: la contrasena. Cuentas de Google: un
    # ID token recien obtenido (confirma que sigue siendo la persona).
    password: str = ""
    id_token: str | None = None


class MessageResponse(BaseModel):
    message: str


class AuthResponse(BaseModel):
    message: str
    user_id: int
    name: str
    email: str
    is_business: bool
    access_token: str
    token_type: str = "bearer"