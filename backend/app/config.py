from functools import lru_cache
from typing import Literal
from pydantic import SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    database_url: str = 'postgresql+psycopg://jain:local-development-only@127.0.0.1:5432/jain'
    environment: Literal['development', 'test', 'production'] = 'development'
    storage_path: str = 'storage/private'
    auth_secret: SecretStr = SecretStr('')
    otp_delivery: Literal['development', 'smtp'] = 'development'
    smtp_host: str = ''
    smtp_port: int = 587
    smtp_username: str = ''
    smtp_password: SecretStr = SecretStr('')
    smtp_from: str = ''
    smtp_security: Literal['starttls', 'ssl'] = 'starttls'

    @model_validator(mode='after')
    def production_configuration(self):
        if self.environment == 'production':
            if len(self.auth_secret.get_secret_value()) < 32:
                raise ValueError('Production requires a random AUTH_SECRET of at least 32 characters')
            if self.otp_delivery != 'smtp' or not self.smtp_host or not self.smtp_from:
                raise ValueError('Production requires configured SMTP delivery')
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
