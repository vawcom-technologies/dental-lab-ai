"""Copy every R2 bucket to its EU-jurisdiction replacement, then verify.

Old buckets come from the current env (R2_*_BUCKET, default endpoint). New ones
from NEW_R2_*_BUCKET (same suffixes), reached via the EU endpoint. If the new
buckets use a different API token, set NEW_R2_ACCESS_KEY_ID / NEW_R2_SECRET_ACCESS_KEY.

    python scripts/migrate_r2_to_eu.py            # dry run: list what would be copied
    python scripts/migrate_r2_to_eu.py --apply    # copy missing/changed objects
    python scripts/migrate_r2_to_eu.py --verify   # compare counts, sizes, ETags

Keys are kept identical, so database rows need no rewrite. Safe to re-run: objects
already present with the same size and ETag are skipped. Never deletes anything.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import boto3

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.core.config import settings  # noqa: E402

# env suffix -> old bucket (chat images share documents, so 7 buckets in all)
SUFFIXES = ("VOICE", "DOCUMENTS", "VIDEOS", "PATIENT_IMAGES", "SCANS", "SHADES", "SMILES")


def client(account: str, access: str, secret: str, jurisdiction: str = ""):
    host = f"{account}.{jurisdiction}.r2" if jurisdiction else f"{account}.r2"
    return boto3.client(
        "s3",
        endpoint_url=f"https://{host}.cloudflarestorage.com",
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name="auto",
    )


def listing(c, bucket: str) -> dict[str, tuple[int, str]]:
    out: dict[str, tuple[int, str]] = {}
    for page in c.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        for o in page.get("Contents", []):
            out[o["Key"]] = (o["Size"], o["ETag"].strip('"'))
    return out


def same(a: tuple[int, str], b: tuple[int, str]) -> bool:
    # Multipart ETags (contain "-") depend on part size, so fall back to size only.
    return a[0] == b[0] and ("-" in a[1] or "-" in b[1] or a[1] == b[1])


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    account = settings.r2_account_id
    old = client(account, settings.r2_access_key_id, settings.r2_secret_access_key)
    new = client(
        account,
        os.environ.get("NEW_R2_ACCESS_KEY_ID") or settings.r2_access_key_id,
        os.environ.get("NEW_R2_SECRET_ACCESS_KEY") or settings.r2_secret_access_key,
        os.environ.get("NEW_R2_JURISDICTION", "eu"),
    )

    problems = 0
    for suffix in SUFFIXES:
        src = getattr(settings, f"r2_{suffix.lower()}_bucket")
        dst = os.environ.get(f"NEW_R2_{suffix}_BUCKET", "")
        if not src or not dst:
            print(f"{suffix}: skipped (R2_{suffix}_BUCKET or NEW_R2_{suffix}_BUCKET unset)")
            problems += 1
            continue
        a, b = listing(old, src), listing(new, dst)
        todo = [k for k, v in a.items() if k not in b or not same(v, b[k])]
        print(f"{suffix}: {src} ({len(a)} objects, {sum(v[0] for v in a.values())} B) -> {dst} ({len(b)} objects), {len(todo)} to copy")
        if args.apply:
            for k in todo:
                obj = old.get_object(Bucket=src, Key=k)
                new.upload_fileobj(
                    obj["Body"], dst, k, ExtraArgs={"ContentType": obj.get("ContentType") or "application/octet-stream"}
                )
                print(f"  copied {k}")
            b = listing(new, dst)
        if args.apply or args.verify:
            bad = [k for k, v in a.items() if k not in b or not same(v, b[k])]
            print(f"  verify: {'OK' if not bad else f'{len(bad)} missing or different'}")
            for k in bad[:20]:
                print(f"    {k}")
            problems += bool(bad)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
