"""Thin lazy Milvus connection helper.

Milvus is optional for local dev - the API boots fine without it. Call
`get_milvus()` only from code paths that actually need vector search.
"""

from __future__ import annotations

from functools import lru_cache

from app.core.config import settings


@lru_cache
def get_milvus():
    """Return a connected MilvusClient, or raise if Milvus is unreachable."""
    from pymilvus import MilvusClient  # imported lazily to keep startup light

    return MilvusClient(uri=f"http://{settings.milvus_host}:{settings.milvus_port}")
