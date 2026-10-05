from pydantic import BaseModel


class RegisterTokenRequest(BaseModel):
    token: str
    platform: str = "android"


class RegisterTokenResponse(BaseModel):
    message: str