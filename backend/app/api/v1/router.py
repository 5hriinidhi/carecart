"""Aggregate v1 API router."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import (
    analytics,
    auth,
    health,
    history,
    nudges,
    products,
    scan,
    vault,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(products.router)
api_router.include_router(scan.router)
api_router.include_router(history.router)
api_router.include_router(analytics.router)
api_router.include_router(nudges.router)
for _vault_router in vault.ROUTERS:
    api_router.include_router(_vault_router)
