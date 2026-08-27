"""Application settings, loaded from environment / .env.

Precedence: real environment variables > backend/.env > the defaults below.
Third-party API keys have NO default and must be supplied via .env (see
.env.example). Local-infra values carry dev defaults so `uvicorn app.main:app`
boots with zero config.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # --- app ---
    app_name: str = "CareCart API"
    environment: str = "development"  # development | staging | production
    debug: bool = True
    api_v1_prefix: str = "/api/v1"
    cors_origins: str = "*"  # comma-separated origins, or "*" for all (dev only)

    # --- PostgreSQL 15+ ---
    # docker-compose reads POSTGRES_USER/PASSWORD/DB from backend/.env to create
    # the database; the app composes DATABASE_URL from the same parts. Inside the
    # compose network POSTGRES_HOST is overridden to "postgres".
    postgres_user: str = "carecart"
    postgres_password: str = "carecart"
    postgres_db: str = "carecart"
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    # Optional full override; wins over the POSTGRES_* parts above.
    database_url: str | None = None

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        return (
            f"postgresql+psycopg://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    # --- auth ---
    jwt_secret: str = "dev-only-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days

    # --- third-party API keys (NO defaults - set in .env) ---
    otp_provider_api_key: str = ""
    claude_api_key: str = ""
    openfda_api_key: str = ""
    usda_fdc_api_key: str = ""

    # --- vector database (Milvus) ---
    milvus_host: str = "localhost"
    milvus_port: int = 19530

    # --- graph database (Neo4j, Phase 6+) ---
    neo4j_uri: str = "bolt://localhost:7687"
    neo4j_user: str = "neo4j"
    neo4j_password: str = "carecart-neo4j"

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
