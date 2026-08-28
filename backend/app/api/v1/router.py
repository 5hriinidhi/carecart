"""Aggregate v1 API router."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import auth, health, products, vault

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(products.router)
for _vault_router in vault.ROUTERS:
    api_router.include_router(_vault_router)

# add feature routers here as they land:
# api_router.include_router(scans.router, prefix="/scans", tags=["scans"])
