"""Automatic case status (docs/roadmap.md → Status flow).

Every scan / shade / smile change, sharing with the lab, "Submit to lab" and the
lab's review go through here, so the rules live in one place.
"""

from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException, status

from app.core.security import AuthUser, canonicalize_role
from app.core.supabase_client import get_supabase_admin
from app.services import case_status
from app.services import patient_access as pa
from app.services import patient_media as pm
from app.services.notify import notify
from app.services.profiles import fetch_profile, lab_name
from app.services.r2 import upload_patient_asset

LOCKED = ("in_review", "completed")
REVIEWABLE = ("in_review", "rejected")
# Dentist edits logged on a rejected case (status unchanged).
_EDIT_EVENTS = ("updated", "suggestion_accepted", "suggestion_dismissed")
_TABLES = {"scan": ("patient_scans", "scans"), "shade": ("shade_detections", "shades"), "smile": ("smile_previews", "smiles")}
_ITEM_KEYS = tuple(_TABLES)


def pack_rejection(remarks: str, items: list[dict[str, Any]] | None) -> str:
    """Store overall remarks + optional per-item feedback as JSON in case_events.remarks."""
    if not items:
        return remarks
    return json.dumps({"text": remarks, "items": items}, ensure_ascii=False)


def unpack_rejection(raw: str | None) -> tuple[str | None, list[dict[str, Any]] | None]:
    if not raw:
        return None, None
    text = raw.strip()
    if text.startswith("{"):
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            return raw, None
        if isinstance(data, dict) and "items" in data:
            items = data.get("items")
            note = (data.get("text") or "").strip() or None
            return note, items if isinstance(items, list) else None
    return raw, None


def format_rejection_notify(remarks: str, items: list[dict[str, Any]] | None) -> str:
    parts = [remarks] if remarks else []
    for row in items or []:
        key = str(row.get("item") or "")
        st = str(row.get("status") or "")
        note = (row.get("note") or "").strip()
        if st == "needs_work":
            parts.append(f"{key}: needs work" + (f" — {note}" if note else ""))
        elif st == "ok":
            parts.append(f"{key}: ok")
    return "; ".join(parts) if parts else remarks


def _role(user: AuthUser) -> str:
    return canonicalize_role(user.role, default="")


# ── guards ───────────────────────────────────────────────────────────────────


def require_can_change(user: AuthUser, patient: dict[str, Any] | None = None) -> None:
    """Labs never change the dentist's items (they suggest — see edit_mode).
    With [patient]: only its owning dentist (or the admin) changes case items."""
    role = _role(user)
    if role == "laboratory":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Labs can review cases but not change scans, shades or smile previews."
        )
    if patient is not None and role != "admin" and str(patient.get("created_by") or "") != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the patient's dentist can change this case.")


def edit_mode(user: AuthUser, patient: dict[str, Any]) -> str:
    """'suggest' for the reviewing lab (case under review), else 'edit' (owner) or 403."""
    if _role(user) == "laboratory" and patient.get("status") == "in_review" and _shared_lab(patient) == user.id:
        return "suggest"
    require_can_change(user, patient)
    return "edit"


def require_can_delete(user: AuthUser, table: str, row_id: str) -> None:
    row = pm.fetch_row(table, row_id)
    require_can_change(user, pa.fetch_patient(str(row.get("patient_id") or "")) if row else None)
    if row is not None:
        require_unlocked(str(row.get("patient_id") or ""))


def require_unlocked(patient_id: str) -> None:
    """Under review / completed: items can only be replaced, not deleted."""
    patient = pa.fetch_patient(patient_id)
    if patient and patient.get("status") in LOCKED:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "This case is with the lab. Replace the item instead of deleting it.", "code": "CASE_LOCKED"},
        )


# ── facts ────────────────────────────────────────────────────────────────────


def items(patient_id: str) -> dict[str, bool]:
    """Which case items are present. Scans only count when saved onto the case."""
    out = {}
    for name, (table, _) in _TABLES.items():
        q = get_supabase_admin().table(table).select("id").eq("patient_id", patient_id).limit(1)
        if name == "shade":  # only a shade with a saved analysis counts
            q = q.not_.is_("analysis", "null")
        if name == "scan":  # only scans saved onto the case
            q = q.eq("on_case", True)
        try:
            out[name] = bool(getattr(q.execute(), "data", None))
        except Exception as exc:
            raise pa.db_error(exc) from exc
    return out


def ready_to_submit(patient: dict[str, Any], *, updated_since_rejection: bool = False) -> bool:
    """True when the client should ask "Submit now?": a complete, shared case in
    progress, or a rejected case the dentist has changed since (resubmit)."""
    st = patient.get("status")
    if st == "rejected":
        if not updated_since_rejection or suggestions(patient):
            return False
    elif st != "in_progress" or patient.get("auto_submit") is False:
        return False
    lab = _shared_lab(patient)
    return lab is not None and all(items(str(patient["id"])).values())


def owner_lab(patient: dict[str, Any]) -> str | None:
    """The reviewing lab: the owner dentist's lab."""
    owner = fetch_profile(str(patient.get("created_by") or ""))
    if not owner or owner.get("role") != "dentist":
        return None
    return str(owner.get("lab_id") or "") or None


def _shared_lab(patient: dict[str, Any]) -> str | None:
    lab = owner_lab(patient)
    return lab if lab and pa.has_shared_access(str(patient["id"]), lab) else None


# ── transitions ──────────────────────────────────────────────────────────────


def _submit(patient: dict[str, Any], lab_id: str, actor_id: str, remarks: str | None) -> dict[str, Any]:
    patient = case_status.set_status(
        patient, "in_review", actor_id=actor_id, type="submitted", remarks=remarks, auto_submit=True
    )
    if lab_review(patient).get("dentist_updated"):
        _touch(str(patient["id"]), dentist_updated=False)
    notify(
        user_id=lab_id,
        type="case_status",
        message=f"{pa.patient_display_name(patient)} was submitted for review.",
        patient_id=str(patient["id"]),
        actor_id=actor_id,
    )
    return patient


def after_change(patient_id: str, actor_id: str, *, scan: bool = False) -> dict[str, Any] | None:
    """Call after a scan is saved to the case, or shade/smile Accept/Save."""
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        return None
    st = patient.get("status") or "pending"
    if st == "pending":
        if not scan:
            return patient
        return case_status.set_status(patient, "in_progress", actor_id=actor_id, type="scan_added")
    if st == "rejected":
        # Stays in the lab's Rejected tab (marked updated) until the dentist resubmits.
        case_status.log_event(patient_id, actor_id=actor_id, type="updated", to_status=st)
        _touch(patient_id, dentist_updated=True)
        lab = _shared_lab(patient)
        if lab:
            notify(
                user_id=lab,
                type="case_status",
                message=f"{pa.patient_display_name(patient)} was updated by the dentist.",
                patient_id=patient_id,
                actor_id=actor_id,
            )
        return patient
    if st in LOCKED:
        lab = _shared_lab(patient)
        if st == "completed":
            patient = case_status.set_status(
                patient, "in_review" if lab else "in_progress", actor_id=actor_id, type="reopened"
            )
        else:
            case_status.log_event(patient_id, actor_id=actor_id, type="updated", to_status=st)
        if lab:
            verb = "reopened" if st == "completed" else "updated"
            notify(
                user_id=lab,
                type="case_status",
                message=f"{pa.patient_display_name(patient)} was {verb} by the dentist.",
                patient_id=patient_id,
                actor_id=actor_id,
            )
        return patient
    return patient


def submit(patient: dict[str, Any], user: AuthUser, *, confirm_incomplete: bool) -> dict[str, Any]:
    """"Submit to lab": shares with the owner's lab and turns automatic submission back on."""
    require_can_change(user, patient)
    if patient.get("status") in LOCKED:
        raise HTTPException(status.HTTP_409_CONFLICT, "This case is already with the lab")
    if suggestions(patient):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "Accept or dismiss the lab's suggestions first.", "code": "SUGGESTIONS_PENDING"},
        )
    lab = owner_lab(patient)
    if lab is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "The patient's dentist isn't linked to a lab yet.")
    missing = [name for name, ok in items(str(patient["id"])).items() if not ok]
    if missing and not confirm_incomplete:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "Some items are missing.", "code": "INCOMPLETE", "missing": missing},
        )
    if not pa.has_shared_access(str(patient["id"]), lab):
        now = pa.utc_now_iso()
        try:
            get_supabase_admin().table("patient_access").upsert(
                {
                    "patient_id": str(patient["id"]),
                    "user_id": lab,
                    "granted_by": user.id,
                    "requested_by": user.id,
                    "approved_by": user.id,
                    "status": "approved",
                    "created_at": now,
                },
                on_conflict="patient_id,user_id",
            ).execute()
        except Exception as exc:
            raise pa.db_error(exc) from exc
    remarks = f"Submitted without: {', '.join(missing)}" if missing else None
    return _submit(patient, lab, user.id, remarks)


def _normalize_item_feedback(items: list[dict[str, Any]] | None) -> list[dict[str, Any]] | None:
    if not items:
        return None
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in items:  # item/status already checked by ItemFeedbackIn
        key, st = raw["item"], raw["status"]
        note = (raw.get("note") or "").strip() or None
        if key in seen:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Duplicate feedback for {key}")
        if st == "needs_work" and not note:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, f"A note is required when marking {key} as needs work")
        seen.add(key)
        out.append({"item": key, "status": st, "note": note})
    return out


def review(
    patient: dict[str, Any],
    user: AuthUser,
    *,
    approve: bool,
    remarks: str | None,
    items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """The owner's lab (or the admin) approves → completed, or rejects with remarks / item notes."""
    is_admin = _role(user) == "admin"
    if not is_admin and _shared_lab(patient) != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the patient's lab can review this case.")
    # Rejected stays decidable: the lab can approve after all, or update its remarks.
    if patient.get("status") not in REVIEWABLE:
        raise HTTPException(status.HTTP_409_CONFLICT, "This case isn't waiting for review")
    remarks = (remarks or "").strip() or None
    pending = suggestions(patient)
    if approve and pending:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "You suggested changes — reject so the dentist can confirm them.", "code": "SUGGESTIONS_PENDING"},
        )
    feedback = None if approve else _normalize_item_feedback(items)
    if pending and not approve:
        # A lab change always goes back to the dentist to confirm.
        remarks = remarks or "Lab made changes, please confirm."
        given = {f["item"]: f for f in feedback or []}
        for key in pending:
            note = (given.get(key) or {}).get("note") or "Lab suggested a change — please review."
            given[key] = {"item": key, "status": "needs_work", "note": note}
        feedback = [given[k] for k in _ITEM_KEYS if k in given]
    if not approve and not remarks:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Remarks are required when rejecting")
    if lab_review(patient).get("feedback"):
        _patch_lab_review(str(patient["id"]), ["feedback"], None)
    stored = remarks if approve or not feedback else pack_rejection(remarks or "", feedback)
    patient = case_status.set_status(
        patient,
        "completed" if approve else "rejected",
        actor_id=user.id,
        type="approved" if approve else "rejected",
        remarks=stored,
        auto_submit=None if approve else False,
    )
    name = pa.patient_display_name(patient)
    notify_detail = format_rejection_notify(remarks or "", feedback) if not approve else None
    notify(
        user_id=str(patient.get("created_by") or ""),
        type="case_status",
        message=f"The lab approved {name}." if approve else f"The lab rejected {name}: {notify_detail}",
        patient_id=str(patient["id"]),
        actor_id=user.id,
    )
    return patient


# ── lab review workspace: draft feedback + suggestions (patients.lab_review) ─

def lab_review(patient: dict[str, Any]) -> dict[str, Any]:
    raw = patient.get("lab_review")
    return dict(raw) if isinstance(raw, dict) else {}


def suggestions(patient: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {k: v for k, v in (lab_review(patient).get("suggestions") or {}).items() if isinstance(v, dict)}


def _patch_lab_review(patient_id: str, path: list[str], value: Any, *, bump: bool = False) -> None:
    """Set one key of patients.lab_review in place (None removes it), atomically in
    the database (migration 025), so concurrent lab actions don't overwrite each
    other. [bump] also moves updated_at (the lab's queue sorts it to the top)."""
    try:
        get_supabase_admin().rpc(
            "lab_review_set", {"p_id": patient_id, "p_path": path, "p_value": value, "p_bump": bump}
        ).execute()
    except Exception as exc:
        raise pa.db_error(exc) from exc


def _touch(patient_id: str, *, dentist_updated: bool) -> None:
    """Set or clear the "updated by dentist" marker the lab's queue shows on rejected cases."""
    _patch_lab_review(patient_id, ["dentist_updated"], dentist_updated, bump=True)


def suggestion_id(patient_id: str, item: str) -> str:
    """Synthetic row id for a suggestion, so /api/files and the tool pages can use it."""
    return f"s-{patient_id}-{item}"


def parse_suggestion_id(row_id: str) -> tuple[str, str] | None:
    if not row_id.startswith("s-"):
        return None
    pid, _, item = row_id[2:].rpartition("-")
    return (pid, item) if pid and item in _ITEM_KEYS else None


def suggestion_row(patient: dict[str, Any], item: str) -> dict[str, Any] | None:
    """The suggestion shaped like a row of its table (id = synthetic id)."""
    s = suggestions(patient).get(item)
    if not s:
        return None
    pid = str(patient["id"])
    return {
        **(s.get("extra") or {}),
        "id": suggestion_id(pid, item),
        "patient_id": pid,
        "uploaded_by": s.get("by"),
        "file_key": s.get("file_key"),
        "file_name": s.get("file_name"),
        "format": s.get("format"),
        "created_at": s.get("at"),
        "suggestion_for": s.get("for_id"),
        "on_case": True,
    }


def suggestion_base(patient: dict[str, Any], item: str, row_id: str) -> tuple[dict[str, Any], str | None]:
    """What a lab edit of [row_id] builds on, and which dentist item it stands in for.
    Editing the lab's own suggestion (or the item it replaces) keeps building on it."""
    s = suggestions(patient).get(item)
    if s and row_id in (suggestion_id(str(patient["id"]), item), s.get("for_id")):
        return suggestion_row(patient, item) or {}, s.get("for_id")
    row = pm.fetch_row(_TABLES[item][0], row_id)
    if row is None or str(row.get("patient_id")) != str(patient["id"]):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found")
    return row, row_id


def with_suggestion(patient: dict[str, Any], user: AuthUser, item: str, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Lists for the reviewing lab show its suggestion in place of the item it replaces."""
    fake = suggestion_row(patient, item)
    if fake is None or _role(user) != "laboratory":
        return rows
    target = fake.get("suggestion_for")
    return [fake, *(r for r in rows if str(r.get("id")) != str(target))]


def _drop_files(patient_id: str, item: str, s: dict[str, Any], keep: set[str] = frozenset()) -> None:
    table, kind = _TABLES[item]
    for key in {s.get("file_key"), (s.get("extra") or {}).get("base_file_key")} - {None, ""} - keep:
        pm.delete_file_if_unused(table=table, kind=kind, patient_id=patient_id, file_key=str(key))


def suggest(
    patient: dict[str, Any],
    user: AuthUser,
    item: str,
    *,
    for_id: str | None,
    file_key: str,
    file_name: str | None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Store the lab's proposed change (one per item; a new one replaces the old)."""
    pid = str(patient["id"])
    data = lab_review(patient)
    sugg = dict(data.get("suggestions") or {})
    s = {
        "for_id": for_id,
        "file_key": file_key,
        "file_name": file_name,
        "extra": extra or {},
        "by": user.id,
        "at": pa.utc_now_iso(),
    }
    if item == "scan":
        s["format"] = (file_name or "").rsplit(".", 1)[-1].lower()
    # Fresh read: the file of the suggestion this one replaces gets cleaned up.
    old = suggestions(pa.fetch_patient(pid) or patient).get(item)
    sugg[item] = s
    _patch_lab_review(pid, ["suggestions", item], s)
    if isinstance(old, dict):
        _drop_files(pid, item, old, keep={file_key, str((extra or {}).get("base_file_key") or "")})
    patient = {**patient, "lab_review": {**data, "suggestions": sugg}}
    if not old:
        case_status.log_event(pid, actor_id=user.id, type="lab_suggested", to_status=patient.get("status"), remarks=item)
    return suggestion_row(patient, item) or {}


def suggest_upload(
    patient: dict[str, Any],
    user: AuthUser,
    item: str,
    replaces: str | None,
    *,
    data: bytes,
    filename: str | None,
    content_type: str | None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """A lab upload while reviewing: store the file as a suggestion for [replaces]."""
    for_id = suggestion_base(patient, item, replaces)[1] if replaces else None
    key, url, name = upload_patient_asset(
        data=data, filename=filename, content_type=content_type, kind=_TABLES[item][1], patient_id=str(patient["id"])
    )
    return suggest(patient, user, item, for_id=for_id, file_key=key, file_name=name, extra={**(extra or {}), "file_url": url})


def set_feedback(patient: dict[str, Any], user: AuthUser, item: str, verdict: str | None, note: str | None) -> None:
    """Lab's draft verdict for one item while reviewing; [verdict]=None clears it."""
    if edit_mode(user, patient) != "suggest":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the reviewing lab gives feedback.")
    value = None if verdict is None else {"status": verdict, "note": (note or "").strip() or None}
    _patch_lab_review(str(patient["id"]), ["feedback", item], value)


def resolve_suggestion(patient: dict[str, Any], user: AuthUser, item: str, *, accept: bool) -> dict[str, Any]:
    """The owning dentist accepts (it becomes the case item) or dismisses a lab suggestion.
    Either way it's a change the lab must confirm on resubmit."""
    require_can_change(user, patient)
    if patient.get("status") in LOCKED:
        raise HTTPException(status.HTTP_409_CONFLICT, "This case is with the lab")
    pid = str(patient["id"])
    s = suggestions(patient).get(item)
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No suggestion for this item")
    if accept:
        _apply(pid, item, s)
    _patch_lab_review(pid, ["suggestions", item], None)
    if not accept:
        _drop_files(pid, item, s)
    case_status.log_event(
        pid, actor_id=user.id, type="suggestion_accepted" if accept else "suggestion_dismissed",
        to_status=patient.get("status"), remarks=item,
    )
    return after_change(pid, user.id, scan=item == "scan") or patient


def _apply(patient_id: str, item: str, s: dict[str, Any]) -> None:
    table, kind = _TABLES[item]
    extra = dict(s.get("extra") or {})
    if item == "scan":
        extra["on_case"] = True
    row = pm.find_row_by_key(table, patient_id, str(s["file_key"]))
    if row is not None:
        row = pm.update_row(table, str(row["id"]), extra) if extra else row
    else:
        new = {
            "patient_id": patient_id,
            "uploaded_by": s.get("by"),
            "file_key": s["file_key"],
            "file_url": "",
            "file_name": s.get("file_name") or "",
            "created_at": pa.utc_now_iso(),
            **extra,
        }
        if item == "scan":
            new["format"] = s.get("format") or ""
        row = pm.insert_row(table, new)
    old = pm.fetch_row(table, str(s["for_id"])) if s.get("for_id") else None
    if old and str(old["id"]) != str(row["id"]):
        if item == "scan":
            pm.update_row(table, str(old["id"]), {"on_case": False})  # back to the library
        else:
            pm.remove_replaced(table, kind, old, keep_id=str(row["id"]))


def summary(patient: dict[str, Any], user: AuthUser) -> dict[str, Any]:
    """Everything the app needs to show the case state and its actions."""
    pid = str(patient["id"])
    have = items(pid)
    lab_id = owner_lab(patient)
    lab = fetch_profile(lab_id) if lab_id else None
    shared = bool(lab_id) and pa.has_shared_access(pid, lab_id)
    st = patient.get("status") or "pending"
    try:
        events = getattr(
            get_supabase_admin().table("case_events").select("*").eq("patient_id", pid).order("created_at").execute(),
            "data",
            None,
        ) or []
    except Exception as exc:
        raise pa.db_error(exc) from exc
    names: dict[str, str | None] = {}
    for actor in {str(e.get("actor_id") or "") for e in events} - {""}:
        names[actor] = pa.profile_display_name(fetch_profile(actor), fallback="") or None
    owner = fetch_profile(str(patient.get("created_by") or "")) or {}
    rejection = None
    for e in reversed(events):
        if e.get("to_status") == "rejected" and e.get("type") not in _EDIT_EVENTS:
            rejection = e
            break
        if e.get("type") in ("submitted", "approved"):
            break  # dealt with: resubmitted or approved since
    updated_since = st == "rejected" and bool(lab_review(patient).get("dentist_updated"))
    role = _role(user)
    rej_text, rej_items = unpack_rejection(rejection.get("remarks") if rejection else None)

    def _event_remarks(raw: str | None) -> str | None:
        text, items = unpack_rejection(raw)
        if not items:
            return text
        return format_rejection_notify(text or "", items) or text

    return {
        "status": st,
        "auto_submit": patient.get("auto_submit") is not False,
        "items": have,
        "missing": [k for k, ok in have.items() if not ok],
        "lab": {"id": lab_id, "name": pa.profile_display_name(lab, fallback="") or None} if lab_id else None,
        "owner": {
            "id": str(patient.get("created_by") or ""),
            "name": pa.profile_display_name(owner, fallback="") or None,
            "role": owner.get("role"),
            "clinic_name": owner.get("clinic_name"),
            "lab_name": lab_name(owner),
            "avatar_url": owner.get("avatar_url"),
        },
        "shared_with_lab": shared,
        "ready_to_submit": ready_to_submit(patient, updated_since_rejection=updated_since),
        "updated_since_rejection": updated_since,
        "is_owner": user.id == str(patient.get("created_by") or ""),
        "can_submit": (role == "admin" or user.id == str(patient.get("created_by") or ""))
        and bool(lab_id)
        and st not in LOCKED,
        "can_suggest": st == "in_review" and role == "laboratory" and shared and user.id == lab_id,
        "lab_review": {
            "feedback": lab_review(patient).get("feedback") or {} if role in ("laboratory", "admin") else {},
            "suggestions": {
                k: {
                    "id": suggestion_id(pid, k),
                    "for_id": v.get("for_id"),
                    "file_name": v.get("file_name"),
                    "at": v.get("at"),
                    "by": names.get(str(v.get("by") or "")) or (pa.profile_display_name(fetch_profile(str(v.get("by") or "")), fallback="") or None),
                }
                for k, v in suggestions(patient).items()
            },
        },
        "can_review": st in REVIEWABLE and (role == "admin" or (shared and user.id == lab_id)),
        "last_rejection": {
            "remarks": rej_text,
            "items": rej_items,
            "by": names.get(str(rejection.get("actor_id") or "")),
            "at": rejection.get("created_at"),
        }
        if rejection
        else None,
        "events": [
            {
                "type": e.get("type"),
                "actor_name": names.get(str(e.get("actor_id") or "")),
                "remarks": _event_remarks(e.get("remarks")),
                "from_status": e.get("from_status"),
                "to_status": e.get("to_status"),
                "created_at": e.get("created_at"),
            }
            for e in events
        ],
    }
