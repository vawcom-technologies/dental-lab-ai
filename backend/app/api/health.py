import logging

from fastapi import APIRouter

router = APIRouter()
logger = logging.getLogger("app.api.health")


@router.get("/health")
def health():
    logger.debug("health check")
    return {"status": "ok", "service": "dental-lab-ai", "week": 1}
