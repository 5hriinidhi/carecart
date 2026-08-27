"""Typed application settings + fail-fast loader.

Every value comes from real env vars > backend/.env > the defaults below.
`settings` (bottom of this module) is the ONE cached instance the rest of the
app imports - never read os.environ directly elsewhere.

Startup contract:
  * REQUIRED settings missing/empty  -> ConfigError naming each one, app won't start.
  * OPTIONAL third-party keys missing -> allowed in dev; main.py logs which
    features are degraded. Enforced (also -> ConfigError) when ENVIRONMENT=production.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import ValidationError, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ConfigError(RuntimeError):
    """Raised at startup when required configuration is missing or invalid."""


# attr -> ENV_NAME. Always required; app refuses to start if empty.
# (jwt_secret is handled separately: blank -> dev placeholder, enforced in prod.)
_ALWAYS_REQUIRED: dict[str, str] = {
    "postgres_user": "POSTGRES_USER",
    "postgres_password": "POSTGRES_PASSWORD",
    "postgres_db": "POSTGRES_DB",
    "postgres_host": "POSTGRES_HOST",
    "postgres_port": "POSTGRES_PORT",
}

# attr -> (ENV_NAME, feature that breaks without it). Optional in dev.
_OPTIONAL_KEYS: dict[str, tuple[str, str]] = {
    "otp_provider_api_key": ("OTP_PROVIDER_API_KEY", "phone / OTP sign-in"),
    "claude_api_key": ("CLAUDE_API_KEY", "LLM ingredient fallback + verdict explanations"),
    "openfda_api_key": ("OPENFDA_API_KEY", "openFDA drug-label / interaction lookups"),
    "usda_fdc_api_key": ("USDA_FDC_API_KEY", "USDA FoodData Central nutrient enrichment"),
}

_DEV_JWT_SECRET = "dev-only-change-me"


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

    # --- PostgreSQL 15+ (dev creds, not secrets) ---
    postgres_user: str = "carecart"
    postgres_password: str = "carecart"
    postgres_db: str = "carecart"
    postgres_host: str = "localhost"  # docker-compose overrides -> "postgres"
    postgres_port: int = 5432
    database_url: str | None = None  # full override; wins over the parts above

    # --- auth ---
    jwt_secret: str = _DEV_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days

    # --- third-party API keys (optional in dev; no defaults) ---
    otp_provider_api_key: str = ""
    claude_api_key: str = ""
    openfda_api_key: str = ""
    usda_fdc_api_key: str = ""

    # --- vector database (Milvus) ---
    milvus_host: str = "localhost"  # docker-compose overrides -> "milvus"
    milvus_port: int = 19530

    @field_validator("jwt_secret", mode="after")
    @classmethod
    def _default_blank_jwt_secret(cls, v: str) -> str:
        # `JWT_SECRET=` (blank) in .env -> fall back to the dev placeholder, which
        # missing_required() then rejects when ENVIRONMENT=production.
        return v.strip() or _DEV_JWT_SECRET

    # --- graph database (Neo4j, Phase 6+) ---
    neo4j_uri: str = "bolt://localhost:7687"
    neo4j_user: str = "neo4j"
    neo4j_password: str = "carecart-neo4j"

    # ------------------------------------------------------------------ derived
    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        return (
            f"postgresql+psycopg://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    @property
    def sqlalchemy_url_safe(self) -> str:
        """sqlalchemy_url with the password masked - safe to log."""
        url = self.sqlalchemy_url
        if "@" in url and "://" in url:
            scheme, rest = url.split("://", 1)
            creds, host = rest.split("@", 1)
            user = creds.split(":", 1)[0]
            return f"{scheme}://{user}:***@{host}"
        return url

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.strip().lower() == "production"

    # ---------------------------------------------------------------- validation
    def missing_required(self) -> list[str]:
        """Human-readable problems with required config. Empty list == OK."""
        problems: list[str] = []
        for attr, env in _ALWAYS_REQUIRED.items():
            value = getattr(self, attr, None)
            if value is None or str(value).strip() == "":
                problems.append(f"{env} is required but is empty")

        if self.is_production:
            if self.jwt_secret == _DEV_JWT_SECRET:
                problems.append(
                    "JWT_SECRET is still the dev placeholder - set a real secret in production"
                )
            for attr, (env, feature) in _OPTIONAL_KEYS.items():
                if not getattr(self, attr):
                    problems.append(f"{env} is required in production (feature: {feature})")
        return problems

    def optional_key_status(self) -> list[tuple[str, bool, str]]:
        """(ENV_NAME, present?, feature) for each optional third-party key."""
        return [
            (env, bool(getattr(self, attr)), feature)
            for attr, (env, feature) in _OPTIONAL_KEYS.items()
        ]


@lru_cache
def get_settings() -> Settings:
    try:
        cfg = Settings()
    except ValidationError as exc:
        bad = ", ".join(str(e["loc"][0]).upper() for e in exc.errors())
        raise ConfigError(
            f"Invalid value(s) for: {bad}. "
            f"Check backend/.env against backend/.env.example."
        ) from None

    problems = cfg.missing_required()
    if problems:
        listed = "\n".join(f"  - {p}" for p in problems)
        raise ConfigError(
            f"Configuration error - {len(problems)} problem(s) loading settings:\n"
            f"{listed}\n"
            f"Fix: copy backend/.env.example to backend/.env and set the value(s) above."
        )
    return cfg


settings: Settings = get_settings()
