"""One-off cleanup of patient media from before content-hash keys.

Dry run by default (prints the plan, changes nothing):

  cd backend && PYTHONPATH=. .venv/bin/python scripts/cleanup_patient_media.py
  ... --apply                 # do it
  ... --apply --drop-unsaved  # also delete shade/smile rows never saved by a doctor

Per table (shade_detections, smile_previews, patient_scans):
  1. rows whose image no longer exists are deleted
  2. every image moves to its content-hash key in its own bucket (server-side
     copy; camera-photo pointers become real copies in the kind's bucket)
  3. rows of the same patient with the same image collapse to one: a saved
     row (analysis / overlay) wins, else the newest
  4. objects in the kind's bucket that no row uses any more are deleted
The camera bucket (patient-images) is only read, never changed.
"""

from __future__ import annotations

import argparse
import hashlib
from collections import defaultdict
from pathlib import Path

from app.core.supabase_client import get_supabase_admin
from app.services.r2 import bucket_for, get_r2_client

# table -> (kind, column that marks a doctor-saved row)
TABLES = {
    "shade_detections": ("shades", "analysis"),
    "smile_previews": ("smiles", "overlay"),
    "patient_scans": ("scans", None),
}


def list_keys(client, bucket: str) -> set[str]:
    pages = client.get_paginator("list_objects_v2").paginate(Bucket=bucket)
    return {o["Key"] for page in pages for o in page.get("Contents", [])}


def sha256_of(client, bucket: str, key: str) -> str:
    h = hashlib.sha256()
    for chunk in client.get_object(Bucket=bucket, Key=key)["Body"].iter_chunks(1 << 20):
        h.update(chunk)
    return h.hexdigest()


def hash_key(kind: str, patient_id: str, source_key: str, digest: str) -> str:
    # Same layout as r2.build_patient_asset_key (extension from the stored object).
    ext = Path(source_key).suffix.lower() or (".ply" if kind == "scans" else ".jpg")
    return f"patients/{patient_id}/{kind}/{digest}{ext}"


def plan_table(client, table: str, kind: str, saved_col: str | None, drop_unsaved: bool):
    db = get_supabase_admin()
    bucket, public = bucket_for(kind)
    img_bucket, _ = bucket_for("photos")
    own, img = list_keys(client, bucket), list_keys(client, img_bucket)
    rows = db.table(table).select("*").execute().data or []

    delete_rows: list[tuple[dict, str]] = []
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    copies: dict[str, tuple[str, str]] = {}  # new key -> (source bucket, key)
    digests: dict[tuple[str, str], str] = {}
    for row in rows:
        key = str(row.get("file_key") or "")
        if key in own:
            src = (bucket, key)
        elif key in img:
            src = (img_bucket, key)
        else:
            delete_rows.append((row, "image missing"))
            continue
        if drop_unsaved and saved_col and not row.get(saved_col):
            delete_rows.append((row, "never saved"))
            continue
        if src not in digests:
            digests[src] = sha256_of(client, *src)
        new_key = hash_key(kind, str(row["patient_id"]), key, digests[src])
        if new_key not in own:
            copies.setdefault(new_key, src)
        row["_new_key"] = new_key
        groups[(str(row["patient_id"]), new_key)].append(row)

    keep: list[dict] = []
    for group in groups.values():
        group.sort(
            key=lambda r: (bool(saved_col and r.get(saved_col)), str(r.get("created_at") or "")),
            reverse=True,
        )
        keep.append(group[0])
        delete_rows += [(r, "duplicate image") for r in group[1:]]

    used = {r["_new_key"] for r in keep} | {
        str(r.get("base_file_key")) for r in keep if r.get("base_file_key")
    }
    orphans = sorted(k for k in own if k not in used)
    moves = [r for r in keep if r["_new_key"] != r.get("file_key")]
    return {
        "bucket": bucket,
        "public": public,
        "rows": rows,
        "keep": keep,
        "moves": moves,
        "copies": copies,
        "delete_rows": delete_rows,
        "orphans": orphans,
        "unsaved_kept": sum(1 for r in keep if saved_col and not r.get(saved_col)),
    }


def apply(client, table: str, plan: dict) -> None:
    db = get_supabase_admin()
    bucket, public = plan["bucket"], plan["public"]
    for new_key, (src_bucket, src_key) in plan["copies"].items():
        client.copy_object(
            Bucket=bucket,
            Key=new_key,
            CopySource={"Bucket": src_bucket, "Key": src_key},
        )
    for row in plan["moves"]:
        db.table(table).update(
            {"file_key": row["_new_key"], "file_url": f"{public.rstrip('/')}/{row['_new_key']}"}
        ).eq("id", row["id"]).execute()
    for row, _ in plan["delete_rows"]:
        db.table(table).delete().eq("id", row["id"]).execute()
    # Objects last: only once no row points at them.
    for key in plan["orphans"]:
        client.delete_object(Bucket=bucket, Key=key)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--drop-unsaved", action="store_true")
    args = parser.parse_args()
    client = get_r2_client()

    for table, (kind, saved_col) in TABLES.items():
        plan = plan_table(client, table, kind, saved_col, args.drop_unsaved)
        reasons = defaultdict(int)
        for _, why in plan["delete_rows"]:
            reasons[why] += 1
        print(f"\n== {table} ({plan['bucket']})")
        print(f"  rows now:                 {len(plan['rows'])}")
        print(f"  rows after:               {len(plan['keep'])}")
        print(f"  rows to delete:           {dict(reasons) or 0}")
        print(f"  rows to repoint:          {len(plan['moves'])}")
        print(f"  images to copy in-bucket: {len(plan['copies'])}")
        print(f"  objects to delete:        {len(plan['orphans'])}")
        if saved_col:
            print(f"  kept rows never saved:    {plan['unsaved_kept']}"
                  + ("" if args.drop_unsaved else "  (--drop-unsaved removes them)"))
        if args.apply:
            apply(client, table, plan)
            print("  APPLIED")
    if not args.apply:
        print("\nDry run — nothing changed. Re-run with --apply to do it.")


if __name__ == "__main__":
    main()
