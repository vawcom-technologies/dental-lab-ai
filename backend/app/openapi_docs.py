"""Custom OpenAPI extensions — document the WebSocket chat channel in /docs."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from app.schemas_chat import (
    WSErrorEvent,
    WSMarkAsRead,
    WSMessageSend,
    WSMessagesReadEvent,
    WSNewMessageEvent,
)

WS_TAG = "WebSocket Real-Time Messaging"

WS_DESCRIPTION = """
## Real-time 1-to-1 messaging (WebSocket)

> **Note:** Swagger UI cannot open a live WebSocket (“Try it out” is HTTP-only).  
> Use the schemas below + the quick-start guides to test with Postman, Hoppscotch, or a browser console.

### Connection URL

```
ws://<host>/ws/chat?token=<SUPABASE_JWT>
```

Production / TLS:

```
wss://<host>/ws/chat?token=<SUPABASE_JWT>
```

| Query param | Type | Required | Description |
|-------------|------|----------|-------------|
| `token` | string (JWT) | **Yes** | Supabase Auth **access_token** from `POST /api/auth/signin` |

On auth failure the socket closes with code **4401**.

---

### Outgoing actions (Client → Server)

Send JSON text frames. The event discriminator field is **`type`**  
(the server also accepts **`action`** as an alias).

#### `send_message`

```json
{
  "type": "send_message",
  "conversation_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "content": "Hello — can you confirm the shade?",
  "reply_to_message_id": null,
  "media_url": null
}
```

See schema **`WSMessageSend`**.

#### `mark_as_read`

```json
{
  "type": "mark_as_read",
  "conversation_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
}
```

See schema **`WSMarkAsRead`**.

---

### Incoming events (Server → Client)

#### `new_message`

Delivered to **sender and recipient** after a message is persisted.

```json
{
  "type": "new_message",
  "message": {
    "id": "...",
    "conversation_id": "...",
    "sender_id": "...",
    "content": "Hello — can you confirm the shade?",
    "media_url": null,
    "reply_to_message_id": null,
    "reply_to": null,
    "read_at": null,
    "created_at": "2026-08-05T12:00:00+00:00"
  }
}
```

See schema **`WSNewMessageEvent`**.

#### `messages_read`

Pushed when unread incoming messages in a room are marked read.

```json
{
  "type": "messages_read",
  "conversation_id": "...",
  "reader_id": "...",
  "message_ids": ["...", "..."],
  "read_at": "2026-08-05T12:01:00+00:00"
}
```

See schema **`WSMessagesReadEvent`**.

#### `error`

```json
{ "type": "error", "detail": "conversation_id is required" }
```

See schema **`WSErrorEvent`**.

---

### Testing quick-start

#### 1) Postman
1. Sign in via `POST /api/auth/signin` and copy `access_token`.
2. New → **WebSocket** request → URL `ws://127.0.0.1:8000/ws/chat?token=<access_token>`.
3. Connect, then send a `send_message` / `mark_as_read` JSON frame.

#### 2) Hoppscotch
1. Open **Realtime → WebSocket**.
2. URL: `ws://127.0.0.1:8000/ws/chat?token=<access_token>`.
3. Connect and send the same JSON payloads.

#### 3) Browser console

```javascript
const token = "<PASTE_ACCESS_TOKEN>";
const ws = new WebSocket(`ws://127.0.0.1:8000/ws/chat?token=${encodeURIComponent(token)}`);
ws.onopen = () => console.log("connected");
ws.onmessage = (e) => console.log("←", JSON.parse(e.data));
ws.onerror = (e) => console.error(e);
ws.onclose = (e) => console.log("closed", e.code);

// After connect:
ws.send(JSON.stringify({
  type: "send_message",
  conversation_id: "<CONVERSATION_UUID>",
  content: "Hello from browser"
}));
```

### Related REST helpers
- `POST /api/conversations/get-or-create` — open/create a room  
- `GET /api/conversations` — inbox  
- `GET /api/conversations/{id}/messages` — history  
""".strip()


def _schema_ref(name: str) -> dict:
    return {"$ref": f"#/components/schemas/{name}"}


def build_openapi_schema(app: FastAPI) -> dict:
    """Build the default OpenAPI schema and inject WebSocket documentation."""
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
        tags=[
            {
                "name": WS_TAG,
                "description": (
                    "Live WebSocket channel for 1-to-1 messaging. "
                    "Not executable in Swagger UI — use Postman / Hoppscotch / browser."
                ),
            }
        ],
    )

    # Ensure our tag is present even if FastAPI already emitted others
    existing_tags = {t.get("name") for t in openapi_schema.get("tags") or []}
    if WS_TAG not in existing_tags:
        openapi_schema.setdefault("tags", []).append(
            {
                "name": WS_TAG,
                "description": (
                    "Live WebSocket channel for 1-to-1 messaging. "
                    "Not executable in Swagger UI — use Postman / Hoppscotch / browser."
                ),
            }
        )

    components = openapi_schema.setdefault("components", {})
    schemas = components.setdefault("schemas", {})

    # Register Pydantic models under Components → Schemas
    for model in (
        WSMessageSend,
        WSMarkAsRead,
        WSNewMessageEvent,
        WSMessagesReadEvent,
        WSErrorEvent,
    ):
        schemas[model.__name__] = model.model_json_schema(
            ref_template="#/components/schemas/{model}"
        )

    # Inject a documented path (GET is a Swagger-friendly placeholder for WS)
    openapi_schema.setdefault("paths", {})["/ws/chat"] = {
        "get": {
            "tags": [WS_TAG],
            "summary": "WebSocket chat channel",
            "description": WS_DESCRIPTION,
            "operationId": "websocket_chat_docs",
            "parameters": [
                {
                    "name": "token",
                    "in": "query",
                    "required": True,
                    "description": "Supabase Auth JWT access_token from sign-in.",
                    "schema": {"type": "string", "title": "token"},
                }
            ],
            "responses": {
                "101": {
                    "description": "Switching Protocols — WebSocket connection established.",
                },
                "4401": {
                    "description": "Unauthorized — invalid or missing JWT (socket closed).",
                },
            },
            "requestBody": {
                "required": False,
                "description": (
                    "Not an HTTP body. After the WebSocket upgrade, send JSON frames "
                    "matching **WSMessageSend** or **WSMarkAsRead**."
                ),
                "content": {
                    "application/json": {
                        "schema": {
                            "oneOf": [
                                _schema_ref("WSMessageSend"),
                                _schema_ref("WSMarkAsRead"),
                            ]
                        },
                        "examples": {
                            "send_message": {
                                "summary": "send_message",
                                "value": {
                                    "type": "send_message",
                                    "conversation_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                                    "content": "Hello — can you confirm the shade?",
                                    "reply_to_message_id": None,
                                },
                            },
                            "mark_as_read": {
                                "summary": "mark_as_read",
                                "value": {
                                    "type": "mark_as_read",
                                    "conversation_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                                },
                            },
                        },
                    }
                },
            },
            "x-websocket": True,
            "x-websocket-url": "ws://<host>/ws/chat?token=<SUPABASE_JWT>",
        }
    }

    app.openapi_schema = openapi_schema
    return app.openapi_schema


def attach_custom_openapi(app: FastAPI) -> None:
    """Override `app.openapi` with the WebSocket-aware generator."""

    def custom_openapi() -> dict:
        return build_openapi_schema(app)

    app.openapi = custom_openapi  # type: ignore[method-assign]
