"""Aggregate v1 API router."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import health

api_router = APIRouter()
api_router.include_router(health.router)

# add feature routers here as they land:
# api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
# api_router.include_router(profiles.router, prefix="/profiles", tags=["profiles"])
# api_router.include_router(medications.router, prefix="/medications", tags=["medications"])
# api_router.include_router(scans.router, prefix="/scans", tags=["scans"])
