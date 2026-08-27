import pytest

from app.core.config import ConfigError, Settings, get_settings


def test_settings_is_cached_singleton():
    assert get_settings() is get_settings()


def test_dev_defaults_have_no_required_problems():
    assert Settings().missing_required() == []


def test_empty_required_var_is_named_not_generic():
    problems = Settings(postgres_password="").missing_required()
    assert any("POSTGRES_PASSWORD" in p for p in problems)
    assert all("KeyError" not in p for p in problems)


def test_optional_keys_do_not_block_startup_in_dev():
    # all four unset - still fine in development
    assert Settings(environment="development").missing_required() == []


def test_production_enforces_optional_keys_and_real_jwt_secret():
    # blank every optional key explicitly so the result does not depend on
    # whatever a local backend/.env happens to contain
    problems = Settings(
        environment="production",
        jwt_secret="dev-only-change-me",
        otp_provider_api_key="",
        claude_api_key="",
        openfda_api_key="",
        usda_fdc_api_key="",
    ).missing_required()
    joined = " ".join(problems)
    for env in ("OTP_PROVIDER_API_KEY", "CLAUDE_API_KEY", "OPENFDA_API_KEY", "USDA_FDC_API_KEY"):
        assert env in joined
    assert "JWT_SECRET" in joined


def test_production_passes_when_everything_supplied():
    ok = Settings(
        environment="production",
        jwt_secret="a-real-long-secret",
        otp_provider_api_key="x",
        claude_api_key="x",
        openfda_api_key="x",
        usda_fdc_api_key="x",
    )
    assert ok.missing_required() == []


def test_optional_key_status_shape():
    rows = Settings(claude_api_key="present").optional_key_status()
    names = {name for name, _, _ in rows}
    assert names == {
        "OTP_PROVIDER_API_KEY",
        "CLAUDE_API_KEY",
        "OPENFDA_API_KEY",
        "USDA_FDC_API_KEY",
    }
    claude = next(r for r in rows if r[0] == "CLAUDE_API_KEY")
    assert claude[1] is True


def test_sqlalchemy_url_safe_masks_password():
    s = Settings(postgres_password="hunter2")
    assert "hunter2" not in s.sqlalchemy_url_safe
    assert ":***@" in s.sqlalchemy_url_safe


def test_configerror_message_lists_each_missing_var(monkeypatch):
    # simulate a broken .env by feeding empty required values through the loader
    monkeypatch.setenv("POSTGRES_USER", "")
    monkeypatch.setenv("POSTGRES_DB", "")
    get_settings.cache_clear()
    with pytest.raises(ConfigError) as exc:
        get_settings()
    msg = str(exc.value)
    assert "POSTGRES_USER" in msg and "POSTGRES_DB" in msg
    assert "backend/.env" in msg
    get_settings.cache_clear()
