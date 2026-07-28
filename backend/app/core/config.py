from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Dental Lab AI"
    secret_key: str = "dev-only-change-me-week1"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 12
    database_url: str = "sqlite:///./dental_lab.db"
    # GDPR: production must use EU-region Postgres + encrypted storage
    eu_hosting_required: bool = True

    class Config:
        env_file = ".env"


settings = Settings()
