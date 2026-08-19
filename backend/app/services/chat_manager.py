"""In-memory WebSocket connection manager for 1-to-1 chat."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger("app.chat.manager")


class ConnectionManager:
    """Maps authenticated user_id -> active WebSocket."""

    def __init__(self) -> None:
        self._connections: dict[str, WebSocket] = {}

    async def connect(
        self,
        user_id: str,
        websocket: WebSocket,
        *,
        subprotocol: str | None = None,
    ) -> None:
        await websocket.accept(subprotocol=subprotocol)
        # Replace any prior socket for this user (single device / latest wins)
        previous = self._connections.get(user_id)
        if previous is not None and previous is not websocket:
            try:
                await previous.close(code=4000)
            except Exception:
                pass
        self._connections[user_id] = websocket
        logger.debug("ws connected user_id=%s active=%s", user_id, len(self._connections))

    def disconnect(self, user_id: str) -> None:
        if self._connections.pop(user_id, None) is not None:
            logger.debug(
                "ws disconnected user_id=%s active=%s",
                user_id,
                len(self._connections),
            )

    def is_online(self, user_id: str) -> bool:
        return user_id in self._connections

    async def send_json(self, target_user_id: str, payload: dict[str, Any]) -> bool:
        """Deliver JSON to a user if they have an open socket. Returns True if sent."""
        websocket = self._connections.get(target_user_id)
        if websocket is None:
            return False
        try:
            await websocket.send_json(payload)
            return True
        except Exception as exc:
            logger.warning(
                "ws send failed user_id=%s detail=%s — dropping connection",
                target_user_id,
                exc,
            )
            self.disconnect(target_user_id)
            return False


chat_manager = ConnectionManager()
