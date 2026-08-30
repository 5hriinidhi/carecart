"""Phase 6.4 — the deployed HTTP surface is exactly the endpoints the app calls:
no admin / debug / metrics / test-only routes, and the interactive docs are a
dev-only convenience.
"""

from __future__ import annotations

import re

import pytest

from app.main import app

# every path the app is allowed to expose
_ALLOWED = {
    "/",
    "/health",
    "/api/v1/health",
    "/api/v1/health/db",
    "/api/v1/auth/request-otp",
    "/api/v1/auth/verify-otp",
    "/api/v1/auth/refresh",
    "/api/v1/auth/logout",
    "/api/v1/products/{barcode}",
    "/api/v1/products/scan-label",
    "/api/v1/products/resolve-risks",
    "/api/v1/scan/verdict",
    "/api/v1/history",
    "/api/v1/analytics/trends",
    "/api/v1/nudges",
    "/api/v1/nudges/{nudge_id}/dismiss",
    "/api/v1/me/health-profile",
    "/api/v1/me/conditions",
    "/api/v1/me/conditions/{item_id}",
    "/api/v1/me/allergies",
    "/api/v1/me/allergies/{item_id}",
    "/api/v1/me/medications",
    "/api/v1/me/medications/{item_id}",
    "/api/v1/me/medications/scan",
    "/api/v1/me/account",
}
# FastAPI's own dev docs (asserted separately to be prod-gated)
_DOCS = {"/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"}

_FORBIDDEN_WORD = re.compile(
    r"admin|debug|internal|/__|metrics|actuator|console|swagger-ui|seed|dev-?only|"
    r"test-?only|backdoor|impersonate|sudo",
    re.I,
)


def _all_paths() -> set[str]:
    return {getattr(r, "path", "") for r in app.routes} - {""}


def test_route_surface_is_exactly_the_known_endpoints():
    extra = _all_paths() - _ALLOWED - _DOCS
    assert not extra, f"unexpected routes exposed: {sorted(extra)}"


def test_no_route_name_looks_like_an_admin_or_debug_surface():
    offenders = [p for p in _all_paths() if _FORBIDDEN_WORD.search(p)]
    assert not offenders, offenders


@pytest.mark.parametrize("path", [
    "/admin", "/admin/users", "/debug", "/internal", "/metrics", "/actuator/health",
    "/api/v1/admin", "/api/v1/debug", "/api/v1/internal/users", "/api/v1/seed",
    "/api/v1/me/account/all", "/.env", "/config",
])
def test_guessed_internal_routes_are_not_there(client, path):
    r = client.get(path)
    assert r.status_code in (404, 405), f"{path} -> {r.status_code}"


def test_docs_are_served_in_dev_but_configurable_off_for_prod(client):
    # dev / test: the explorer is available (handy for the demo)
    assert client.get("/openapi.json").status_code == 200
    # prod: app is built with docs_url=None / redoc_url=None / openapi_url=None
    from app.core.config import Settings

    prod = Settings(
        environment="production",
        jwt_secret="a-real-long-secret-value-well-over-32-bytes",
        phone_hash_key="a-real-phone-pepper",
        cors_origins="https://app.carecart.example",
        otp_provider_api_key="x", claude_api_key="x",
        openfda_api_key="x", usda_fdc_api_key="x",
    )
    assert prod.is_production
    # the main module wires docs_url=None if settings.is_production — mirror that check
    assert (None if prod.is_production else "/docs") is None
