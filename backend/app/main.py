"""FastAPI application entrypoint.

Run (dev):  uvicorn app.main:app --reload
Docs:       http://localhost:8000/docs
"""

from __future__ import annotations

import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.api.v1.router import api_router
from app.core.config import settings
from app.db.session import engine

logger = logging.getLogger("carecart")
if not logger.handlers:
    _h = logging.StreamHandler(sys.stdout)
    _h.setFormatter(logging.Formatter("%(levelname)s [%(name)s] %(message)s"))
    logger.addHandler(_h)
    logger.setLevel(logging.INFO)
    logger.propagate = False


def _log_startup_config() -> None:
    """Log the config picture at boot - never the secret values themselves."""
    logger.info("environment=%s  debug=%s", settings.environment, settings.debug)
    logger.info("database=%s", settings.sqlalchemy_url_safe)

    present, missing = [], []
    for env_name, is_set, feature in settings.optional_key_status():
        (present if is_set else missing).append((env_name, feature))

    logger.info(
        "third-party API keys present: %s",
        ", ".join(name for name, _ in present) or "(none)",
    )
    for name, feature in missing:
        logger.warning("third-party API key MISSING: %s  ->  degraded: %s", name, feature)
    if missing and not settings.is_production:
        logger.warning(
            "%d optional key(s) missing - the features above will not work in this dev session.",
            len(missing),
        )


@asynccontextmanager
async def lifespan(_: FastAPI):
    _log_startup_config()
    yield
    # shutdown hooks go here


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    debug=settings.debug and not settings.is_production,  # never leak tracebacks in prod
    lifespan=lifespan,
    # the interactive API explorer + schema are a dev convenience; off in prod so
    # the deployed surface is exactly the endpoints the app calls.
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.exception_handler(Exception)
async def _unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
    """Any uncaught error: log the detail server-side, return a generic body so
    no stack trace, SQL, or row data can reach the client."""
    logger.exception("unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


app.include_router(api_router, prefix=settings.api_v1_prefix)


@app.get("/")
def root() -> dict[str, str]:
    return {"service": settings.app_name, "docs": "/docs", "api": settings.api_v1_prefix}


@app.get(
    "/health",
    summary="Liveness + database readiness",
    responses={
        200: {"content": {"application/json": {"example": {"status": "ok", "db": "connected"}}}},
        503: {
            "content": {
                "application/json": {
                    "example": {"status": "error", "db": "disconnected", "reason": "..."}
                }
            }
        },
    },
)
def health() -> JSONResponse:
    """Return 200 only if the app can execute `SELECT 1` against Postgres."""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        return JSONResponse(
            status_code=503,
            content={"status": "error", "db": "disconnected", "reason": str(exc.__cause__ or exc)},
        )
    return JSONResponse(status_code=200, content={"status": "ok", "db": "connected"})
