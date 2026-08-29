"""Phase 3 compliance foundation — the security non-negotiables.

  * app-layer encryption covers EVERY PHI column (see test_vault.py too)
  * no endpoint under /me/ is reachable without a valid JWT (auto-discovered)
  * row-level ownership is enforced, including on the 1:1 health-profile
  * a minimal audit log records who/what/when — never the data's content
  * an unhandled error never leaks internals to the client
  * account deletion also removes the audit trail (nothing left queryable)
"""

from __future__ import annotations

import io
import json
import uuid

import pytest
from sqlalchemy import text
from starlette.requests import Request

from app.core.security import create_access_token, hash_phone
from app.main import _unhandled_exception, app
from app.models import User

BASE = "/api/v1"


def _png() -> bytes:
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (60, 30), "white").save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def auth(db):
    user = User(phone_hash=hash_phone("+919222000001"))
    db.add(user)
    db.flush()
    return user, {"Authorization": f"Bearer {create_access_token(user.id)}"}


# --------------------------------------------------- every /me/ route needs auth
def _me_routes() -> list[tuple[str, str]]:
    """(METHOD, full_path) for every /me/* endpoint, read off the OpenAPI schema
    (a stable public API — FastAPI ≥0.128 nests routers so ``app.routes`` no
    longer exposes fully-prefixed paths)."""
    routes: list[tuple[str, str]] = []
    for path, ops in app.openapi()["paths"].items():
        if "/me/" in path or path.endswith("/me"):
            for method in sorted(m.upper() for m in ops if m.lower() != "parameters"):
                routes.append((method, path))
    return routes


ME_ROUTES = _me_routes()


def test_there_are_me_routes_to_check():
    assert len(ME_ROUTES) >= 15  # sanity: discovery actually found the vault


@pytest.mark.parametrize("method,path", ME_ROUTES)
def test_every_me_endpoint_rejects_a_missing_token(client, method, path):
    url = path.replace("{item_id}", str(uuid.uuid4()))
    r = client.request(method, url)
    assert r.status_code == 401, f"{method} {path} served an unauthenticated request"


@pytest.mark.parametrize("method,path", ME_ROUTES)
def test_every_me_endpoint_rejects_a_garbage_token(client, method, path):
    url = path.replace("{item_id}", str(uuid.uuid4()))
    r = client.request(method, url, headers={"Authorization": "Bearer not.a.jwt"})
    assert r.status_code == 401


# ------------------------------------------------- row-level ownership (1:1 too)
def test_health_profile_is_not_visible_to_another_user(client, db):
    def _login(phone):
        code = client.post(f"{BASE}/auth/request-otp", json={"phone": phone}).json()["dev_code"]
        tok = client.post(
            f"{BASE}/auth/verify-otp", json={"phone": phone, "code": code}
        ).json()["access_token"]
        return {"Authorization": f"Bearer {tok}"}

    a = _login("+919222444444")
    b = _login("+919222555555")
    client.put(f"{BASE}/me/health-profile", headers=a, json={"gender": "female"})

    assert client.get(f"{BASE}/me/health-profile", headers=b).status_code == 404
    patch = client.patch(f"{BASE}/me/health-profile", headers=b, json={"gender": "male"})
    assert patch.status_code == 404
    assert client.delete(f"{BASE}/me/health-profile", headers=b).status_code == 404
    # A's row unchanged
    assert client.get(f"{BASE}/me/health-profile", headers=a).json()["gender"] == "female"


# --------------------------------------------------------------- audit log
def test_audit_log_has_no_content_columns(db):
    q = text(
        "SELECT column_name FROM information_schema.columns WHERE table_name = 'audit_log'"
    )
    cols = {c[0] for c in db.execute(q).all()}
    assert cols == {
        "id", "user_id", "action", "resource", "resource_id", "status_code", "created_at"
    }
    forbidden = ("name", "value", "content", "data", "text", "body", "detail", "payload")
    assert not any(any(f in c for f in forbidden) for c in cols)


def test_access_writes_a_who_what_when_row_without_the_data(client, db, auth):
    user, hdr = auth
    created = client.post(
        f"{BASE}/me/conditions", headers=hdr, json={"condition_name": "Epilepsy"}
    ).json()
    client.get(f"{BASE}/me/conditions/{created['id']}", headers=hdr)
    client.get(f"{BASE}/me/conditions", headers=hdr)

    rows = db.execute(
        text(
            "SELECT action, resource, resource_id, status_code "
            "FROM audit_log WHERE user_id = :u ORDER BY created_at"
        ),
        {"u": user.id},
    ).all()
    seen = {(r.action, r.resource) for r in rows}
    assert ("write", "conditions") in seen
    assert ("read", "conditions") in seen
    assert all(r.status_code in (200, 201) for r in rows)

    # the condition name must appear NOWHERE in the audit table
    blob = db.execute(
        text(
            "SELECT string_agg("
            "  action || '|' || resource || '|' || coalesce(resource_id::text, '') "
            "  || '|' || status_code::text, ' ') FROM audit_log"
        )
    ).scalar_one()
    assert "Epilepsy" not in blob


def test_scanning_a_label_is_audited(client, db, auth):
    user, hdr = auth
    client.post(
        f"{BASE}/me/medications/scan",
        headers=hdr,
        files={"file": ("l.png", _png(), "image/png")},
    )
    n = db.execute(
        text(
            "SELECT count(*) FROM audit_log WHERE user_id = :u AND resource = 'medication_scan'"
        ),
        {"u": user.id},
    ).scalar_one()
    assert n == 1


def test_account_deletion_also_wipes_the_audit_trail(client, db):
    def _login(phone):
        code = client.post(f"{BASE}/auth/request-otp", json={"phone": phone}).json()["dev_code"]
        return client.post(
            f"{BASE}/auth/verify-otp", json={"phone": phone, "code": code}
        ).json()["access_token"]

    ha = {"Authorization": f"Bearer {_login('+919222666666')}"}
    hb = {"Authorization": f"Bearer {_login('+919222777777')}"}
    client.post(f"{BASE}/me/allergies", headers=ha, json={"allergen_name": "Latex"})
    client.post(f"{BASE}/me/allergies", headers=hb, json={"allergen_name": "Iodine"})

    uid_a = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"), {"h": hash_phone("+919222666666")}
    ).scalar_one()
    uid_b = db.execute(
        text("SELECT id FROM users WHERE phone_hash = :h"), {"h": hash_phone("+919222777777")}
    ).scalar_one()

    def audit_count(uid):
        return db.execute(
            text("SELECT count(*) FROM audit_log WHERE user_id = :u"), {"u": uid}
        ).scalar_one()

    assert audit_count(uid_a) >= 1

    assert client.delete(f"{BASE}/me/account", headers=ha).status_code == 204
    assert audit_count(uid_a) == 0            # cascaded away — nothing left queryable
    assert audit_count(uid_b) >= 1            # scoped: B's trail is untouched


def test_every_fk_to_users_is_on_delete_cascade(db):
    """6.2 audit F5: `DELETE /me/account` = `DELETE FROM users` and relies purely
    on DB-level cascade. Any future table added with a `user_id` FK that is NOT
    `ON DELETE CASCADE` would silently orphan personal data on deletion — catch
    that here rather than in a breach post-mortem."""
    rows = db.execute(
        text(
            """
            SELECT tc.table_name, rc.delete_rule
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
              ON tc.constraint_name = ccu.constraint_name
            JOIN information_schema.referential_constraints rc
              ON tc.constraint_name = rc.constraint_name
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND ccu.table_name = 'users' AND ccu.column_name = 'id'
            ORDER BY tc.table_name
            """
        )
    ).all()
    offenders = [t for t, rule in rows if rule != "CASCADE"]
    assert not offenders, f"FK(s) to users.id without ON DELETE CASCADE: {offenders}"
    # sanity: discovery actually found the user-owned tables
    tables = {t for t, _ in rows}
    assert {"conditions", "allergies", "medications", "scan_history", "nudges",
            "health_profiles", "refresh_tokens", "audit_log"} <= tables


# ------------------------------------------- no internal leakage on 500
def test_catch_all_exception_handler_is_registered():
    assert Exception in app.exception_handlers or 500 in app.exception_handlers


async def test_unhandled_error_yields_a_generic_body_with_no_internals():
    scope = {"type": "http", "method": "POST", "path": "/api/v1/me/medications/scan", "headers": []}
    boom = RuntimeError("connect to db as user=carecart password=s3cret  /app/secret/path")

    resp = await _unhandled_exception(Request(scope), boom)

    assert resp.status_code == 500
    assert json.loads(resp.body) == {"detail": "Internal server error"}
    body = resp.body.decode()
    for leak in ("s3cret", "carecart", "RuntimeError", "Traceback", "/app/"):
        assert leak not in body
