"""FastAPI application entrypoint.

Run (dev):  uvicorn app.main:app --reload
Docs:       http://localhost:8000/docs
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.api.v1.router import api_router
from app.core.config import settings
from app.db.session import engine


@asynccontextmanager
async def lifespan(_: FastAPI):
    # startup hooks (warm caches, ping Milvus, etc.) go here
    yield
    # shutdown hooks go here


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    debug=settings.debug,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
