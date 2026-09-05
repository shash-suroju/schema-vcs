from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    catalog_dsn: str
    demo_target_dsn: str | None = None
    app_env: str = "local"


settings = Settings()