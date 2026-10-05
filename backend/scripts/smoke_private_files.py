"""Smoke test for private patient files. Run before/after each bucket flip.

  BASE=https://your-backend EMAIL=... PASSWORD=... python scripts/smoke_private_files.py [patient_id]

Use a demo account/patient. For every file kind it opens the first file the way
the app does (relative path -> backend + auth header) and, if the API still hands
out an absolute public URL, reports whether that URL is reachable anonymously.
"""

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ["BASE"].rstrip("/")


def call(path_or_url, token=None, data=None):
    url = path_or_url if path_or_url.startswith("http") else BASE + path_or_url
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""


def file_rows(obj):
    """Every dict with a file_url, wherever the API envelope puts it."""
    if isinstance(obj, dict):
        if obj.get("file_url"):
            yield obj
        for v in obj.values():
            yield from file_rows(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from file_rows(v)


def main():
    status, body = call(
        "/api/auth/signin",
        data=json.dumps({"email": os.environ["EMAIL"], "password": os.environ["PASSWORD"]}).encode(),
    )
    assert status == 200, f"login failed ({status})"
    token = json.loads(body)["access_token"]

    pid = sys.argv[1] if len(sys.argv) > 1 else None
    if not pid:
        _, body = call("/api/patients", token)
        pid = next(r["id"] for r in file_rows_or_ids(json.loads(body)))
    failures = 0
    for kind, route in [("photos", "photos"), ("scans", "scans"), ("shades", "shade-detections"), ("smiles", "smile-previews")]:
        _, body = call(f"/api/patients/{pid}/{route}", token)
        row = next(iter(file_rows(json.loads(body or b"null"))), None)
        if row is None:
            print(f"{kind:7} SKIP  (no files for this patient)")
            continue
        url = row["file_url"]
        if url.startswith("/"):
            status, data = call(url, token)
            ok = status == 200 and len(data) > 0
            print(f"{kind:7} {'OK  ' if ok else 'FAIL'} backend path -> {status}, {len(data)} bytes")
            failures += not ok
        else:
            status, _ = call(url)
            print(f"{kind:7} INFO  API still returns a public URL; anonymous GET -> {status}")
    sys.exit(1 if failures else 0)


def file_rows_or_ids(obj):
    if isinstance(obj, dict):
        if obj.get("id") and obj.get("name") is not None or obj.get("id") and "first_name" in obj:
            yield obj
        for v in obj.values():
            yield from file_rows_or_ids(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from file_rows_or_ids(v)


if __name__ == "__main__":
    main()
