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
# NOTE: runtime scans are pure table lookups - no live LLM calls. CLAUDE_API_KEY
# is used ONLY by the offline batch job that tags queued unknown ingredients.
_OPTIONAL_KEYS: dict[str, tuple[str, str]] = {
    "otp_provider_api_key": ("OTP_PROVIDER_API_KEY", "phone / OTP sign-in"),
    "openfda_api_key": ("OPENFDA_API_KEY", "openFDA drug-label / interaction data refresh"),
    "usda_fdc_api_key": ("USDA_FDC_API_KEY", "USDA FoodData Central nutrient data refresh"),
    "claude_api_key": ("CLAUDE_API_KEY", "offline batch tagging of unknown ingredients"),
}

# Dev-only placeholders. All three are rejected at startup for ANY environment
# that is not explicitly `development` / `test` (see missing_required -> a deploy
# with ENVIRONMENT unset, `prod`, or `staging` fails closed, not open on these).
# Generate real values:
#   JWT_SECRET      -> secrets.token_urlsafe(48)
#   ENCRYPTION_KEY  -> Fernet.generate_key().decode()
#   PHONE_HASH_KEY  -> secrets.token_urlsafe(32)
_DEV_JWT_SECRET = "dev-only-change-me-not-for-production-use"  # >= 32 bytes (RFC 7518)
_DEV_ENCRYPTION_KEY = "I49r_FgAfGuifDRRvTW5pi6RehT0q1KWV4IB-XHWuXE="
_DEV_PHONE_HASH_KEY = "dev-only-phone-pepper-change-me"


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
    database_url: str | None = None  # full OWNER override; wins over the parts above
    # Least-privilege DML-only DSN the *running app* connects with (Phase 6.2 F1).
    # Blank -> app falls back to the owner DSN (fine for dev, not production).
    # Migrations and tests always use the owner DSN, never this.
    app_database_url: str = ""

    # --- auth: tokens ---
    jwt_secret: str = _DEV_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30              # short-lived access token
    refresh_token_expire_minutes: int = 60 * 24 * 30   # 30-day refresh token

    # --- health vault: encryption at rest + phone pepper ---
    # ENCRYPTION_KEY encrypts the sensitive medication/condition columns (Fernet).
    # ENCRYPTION_KEYS_OLD holds previous keys (comma-separated) so a rotated key
    # can still decrypt old rows (MultiFernet). PHONE_HASH_KEY peppers the HMAC
    # that turns a phone number into users.phone_hash (no plaintext numbers stored).
    encryption_key: str = _DEV_ENCRYPTION_KEY
    encryption_keys_old: str = ""
    phone_hash_key: str = _DEV_PHONE_HASH_KEY

    # --- auth: phone / OTP sign-in ---
    otp_length: int = 6
    otp_ttl_minutes: int = 5                # a code is valid for 5 minutes
    otp_max_per_window: int = 3             # >= 3 request-otp calls...
    otp_rate_window_minutes: int = 10       # ...per phone per 10 minutes -> 429
    otp_max_verify_attempts: int = 5        # wrong guesses before a code is burned
    otp_default_country_code: str = "+91"   # the onboarding UI shows a +91 prefix
    otp_provider_url: str = ""              # provider HTTPS endpoint; blank -> dev console sender
    otp_sender_id: str = "CareCart"         # sender / from-name on the SMS

    # --- third-party API keys (optional in dev; no defaults) ---
    otp_provider_api_key: str = ""
    claude_api_key: str = ""
    openfda_api_key: str = ""
    usda_fdc_api_key: str = ""

    # --- OCR (medication label scan) ---
    ocr_max_upload_bytes: int = 10 * 1024 * 1024  # reject larger uploads before OCR
    ocr_text_max_chars: int = 4000               # cap on the sanitised extracted text
    tesseract_cmd: str = ""                      # path to the tesseract binary; blank -> PATH
    # below this mean word confidence a label scan is flagged low_confidence
    ocr_low_confidence_threshold: float = 0.55

    # --- ingredient risk resolution (Phase 4.3) ---
    # Directory holding the pre-built static reference CSVs (risk_compounds.csv,
    # ingredient_aliases.csv, llm_ingredient_tags.csv, food_risk_tags.csv,
    # risk_nutrient_thresholds.csv). Loaded into Postgres by
    # scripts/load_risk_tables.py; the scan path only ever reads the DB tables,
    # never an LLM. Blank -> the repo's dataset/data_prep folder (see property).
    risk_data_dir: str = ""
    # When the alias / LLM / threshold tables produce nothing for an ingredient
    # it is marked "unverified" and queued for the offline batch job. Set to 0
    # to skip the queue write (the "unverified" marker is still returned).
    risk_queue_unresolved: bool = True

    # --- Open Food Facts (barcode -> product) ---
    off_base_url: str = "https://world.openfoodfacts.org"
    # OFF asks every app to send a descriptive UA; keep contact info real in prod.
    off_user_agent: str = "CareCart/0.1 (backend; https://github.com/5hriinidhi/carecart)"
    off_timeout_seconds: float = 8.0
    product_cache_ttl_hours: int = 24  # >= 24h so we stay within OFF's rate limits

    # --- vector database (Milvus) ---
    milvus_host: str = "localhost"  # docker-compose overrides -> "milvus"
    milvus_port: int = 19530

    @field_validator("jwt_secret", mode="after")
    @classmethod
    def _default_blank_jwt_secret(cls, v: str) -> str:
        # `JWT_SECRET=` (blank) in .env -> fall back to the dev placeholder, which
        # missing_required() rejects unless ENVIRONMENT is development/test.
        return v.strip() or _DEV_JWT_SECRET

    @field_validator("encryption_key", mode="after")
    @classmethod
    def _default_and_check_encryption_key(cls, v: str) -> str:
        v = v.strip() or _DEV_ENCRYPTION_KEY
        from cryptography.fernet import Fernet  # local import: keeps config import cheap

        try:
            Fernet(v.encode())
        except Exception as exc:  # noqa: BLE001
            raise ValueError(
                "ENCRYPTION_KEY must be a urlsafe-base64 32-byte Fernet key "
                '(generate: python -c "from cryptography.fernet import Fernet; '
                'print(Fernet.generate_key().decode())")'
            ) from exc
        return v

    @field_validator("phone_hash_key", mode="after")
    @classmethod
    def _default_blank_phone_hash_key(cls, v: str) -> str:
        return v.strip() or _DEV_PHONE_HASH_KEY

    # --- graph database (Neo4j, Phase 6+) ---
    neo4j_uri: str = "bolt://localhost:7687"
    neo4j_user: str = "neo4j"
    neo4j_password: str = "carecart-neo4j"

    # ------------------------------------------------------------------ derived
    @property
    def _owner_url(self) -> str:
        if self.database_url:
            return self.database_url
        return (
            f"postgresql+psycopg://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )

    @property
    def sqlalchemy_url(self) -> str:
        """DSN the *running app* connects with. Uses the least-privilege
        ``APP_DATABASE_URL`` (carecart_app, DML-only) when set; otherwise the
        owner DSN (fine for local dev, not production — see Phase 6.2 F1)."""
        return self.app_database_url.strip() or self._owner_url

    @property
    def migration_url(self) -> str:
        """DSN for schema work (Alembic) and the test harness (which CREATEs
        databases). Always the owner — never ``APP_DATABASE_URL``."""
        return self._owner_url

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

    @property
    def secrets_must_be_real(self) -> bool:
        """Fail closed: the dev placeholder JWT / encryption / phone-hash keys are
        only tolerated when ENVIRONMENT is explicitly `development` or `test`.
        Anything else (unset, `prod`, `staging`, a typo) requires real values —
        so a misconfigured deploy refuses to boot rather than silently using the
        committed placeholders."""
        return self.environment.strip().lower() not in {"development", "test"}

    @property
    def otp_echo_in_response(self) -> bool:
        """Dev convenience: return the freshly generated OTP in the
        `POST /auth/request-otp` response body so local testing works without a
        real SMS provider. Allow-listed to dev/test only, and never in
        production. The code is still never written to a log in any environment.
        """
        env = self.environment.strip().lower()
        return env in {"development", "test"} and not self.is_production

    @property
    def encryption_keys_old_list(self) -> list[str]:
        return [k.strip() for k in self.encryption_keys_old.split(",") if k.strip()]

    @property
    def risk_data_path(self) -> str:
        """Absolute path to the static risk-reference CSV directory."""
        import os

        if self.risk_data_dir.strip():
            return os.path.abspath(self.risk_data_dir.strip())
        # config.py -> app/core -> app -> backend -> repo root
        repo_root = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..")
        )
        return os.path.join(
            repo_root, "gradient-ascend-mobile-app", "project", "dataset", "data_prep"
        )

    # ---------------------------------------------------------------- validation
    def missing_required(self) -> list[str]:
        """Human-readable problems with required config. Empty list == OK."""
        problems: list[str] = []
        for attr, env in _ALWAYS_REQUIRED.items():
            value = getattr(self, attr, None)
            if value is None or str(value).strip() == "":
                problems.append(f"{env} is required but is empty")

        # Fail closed on the committed dev placeholders for any non-dev/test env.
        if self.secrets_must_be_real:
            if self.jwt_secret == _DEV_JWT_SECRET:
                problems.append(
                    "JWT_SECRET is still the dev placeholder - set a real secret "
                    f"(ENVIRONMENT={self.environment!r} is not development/test)"
                )
            if self.encryption_key == _DEV_ENCRYPTION_KEY:
                problems.append(
                    "ENCRYPTION_KEY is still the dev placeholder - set a real Fernet key"
                )
            if self.phone_hash_key == _DEV_PHONE_HASH_KEY:
                problems.append(
                    "PHONE_HASH_KEY is still the dev placeholder - set a real value"
                )

        if self.is_production:
            if self.cors_origin_list == ["*"]:
                problems.append(
                    "CORS_ORIGINS must be an explicit allow-list in production "
                    "(wildcard origin with allow_credentials=True is unsafe)"
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
