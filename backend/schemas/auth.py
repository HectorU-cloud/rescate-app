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


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str


class DeleteAccountRequest(BaseModel):
    password: str


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