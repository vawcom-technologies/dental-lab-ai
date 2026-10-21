"""Transactional email helpers (Resend). Failures are logged and never raised."""

from __future__ import annotations

import html
import logging
import re
from datetime import datetime

import resend

from app.core.config import settings

logger = logging.getLogger(__name__)

_DEFAULT_FROM = "Elite Dental Support <support@elite-d.de>"
_TEST_FROM_MARKERS = ("onboarding@resend.dev",)
_ANGLE_EMAIL = re.compile(r"<([^>]+)>")


def _from_address() -> str:
    raw = (settings.resend_from_email or "").strip()
    if not raw or any(m in raw.lower() for m in _TEST_FROM_MARKERS):
        return _DEFAULT_FROM
    return raw


def _bare_email(value: str) -> str:
    text = (value or "").strip()
    match = _ANGLE_EMAIL.search(text)
    if match:
        return match.group(1).strip()
    return text


def _admin_inbox() -> str:
    """Admin alerts go to RESEND_WELCOME_TO_EMAIL, else the From address."""
    raw = (settings.resend_welcome_to_email or "").strip()
    if raw and not any(m in raw.lower() for m in _TEST_FROM_MARKERS):
        return raw
    return _bare_email(_from_address())


_STATUS_LABELS = {
    "scheduled": "Geplant / Scheduled",
    "completed": "Abgeschlossen / Completed",
    "cancelled": "Abgesagt / Cancelled",
    "no_show": "Nicht erschienen / No show",
}


def _format_visit_window(start_time: datetime | str, end_time: datetime | str) -> str:
    def _fmt(value: datetime | str) -> str:
        if isinstance(value, datetime):
            return value.strftime("%d %b %Y · %H:%M UTC")
        raw = str(value or "").strip()
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            return parsed.strftime("%d %b %Y · %H:%M UTC")
        except Exception:
            return raw or "—"

    return f"{_fmt(start_time)} → {_fmt(end_time)}"


Pair = tuple[str, str]  # (German, English); users have no stored language, so mails carry both

_DEFAULT_FOOTER: Pair = (
    "Falls Sie diese Nachricht nicht erwartet haben, können Sie sie ignorieren.",
    "If you did not expect this message, you can ignore it.",
)


def _branded_html(*, title: Pair, intro: Pair, details_html: str = "", footer: Pair | None = None) -> str:
    safe_title = html.escape(title[0])
    safe_title_en = html.escape(title[1])
    safe_intro = html.escape(intro[0])
    safe_intro_en = html.escape(intro[1])
    footer = footer or _DEFAULT_FOOTER
    safe_footer = html.escape(footer[0])
    safe_footer_en = html.escape(footer[1])
    details_block = ""
    if details_html:
        details_block = f"""
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 24px;background:#f7faf9;border:1px solid #e2ebe8;border-radius:4px;">
                  <tr>
                    <td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.7;color:#1a2e2a;">
                      {details_html}
                    </td>
                  </tr>
                </table>"""
    return f"""<!DOCTYPE html>
<html>
  <body style="margin:0;padding:0;background:#f4f7f6;font-family:Georgia,'Times New Roman',serif;color:#1a2e2a;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:36px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:580px;background:#ffffff;border-radius:4px;overflow:hidden;border:1px solid #d7e0dd;">
            <tr>
              <td style="background:#0f3d36;padding:28px 32px;">
                <p style="margin:0;font-size:13px;letter-spacing:0.18em;text-transform:uppercase;color:#a8c5be;font-family:Arial,Helvetica,sans-serif;">
                  Elite Dent
                </p>
                <h1 style="margin:10px 0 0;font-size:26px;line-height:1.25;font-weight:normal;color:#ffffff;">
                  {safe_title}
                </h1>
                <p style="margin:6px 0 0;font-size:15px;color:#a8c5be;font-family:Arial,Helvetica,sans-serif;">
                  {safe_title_en}
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:32px;">
                <p style="margin:0 0 20px;font-size:16px;line-height:1.65;font-family:Arial,Helvetica,sans-serif;color:#334155;">
                  {safe_intro}
                </p>
                <p style="margin:0 0 20px;font-size:14px;line-height:1.65;font-family:Arial,Helvetica,sans-serif;color:#64748b;">
                  {safe_intro_en}
                </p>
                {details_block}
                <p style="margin:0;font-size:13px;line-height:1.5;color:#64748b;font-family:Arial,Helvetica,sans-serif;">
                  {safe_footer}<br>{safe_footer_en}
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 32px 28px;border-top:1px solid #eef2f1;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#94a3b8;">
                — Elite Dent · support@elite-d.de
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>"""


def _appointment_email_shell(*, title: Pair, intro: Pair, details_html: str) -> str:
    return _branded_html(
        title=title,
        intro=intro,
        details_html=details_html,
        footer=(
            "Wenn Sie den Termin verschieben möchten, wenden Sie sich bitte an Ihre Praxis.",
            "If you need to reschedule, please contact your clinic.",
        ),
    )


def _signup_notify_html(
    *,
    name: str,
    email: str,
    role: str = "dentist",
    clinic_name: str | None = None,
    phone: str | None = None,
) -> str:
    safe_name = html.escape((name or "").strip() or "N/A")
    safe_email = html.escape((email or "").strip() or "N/A")
    safe_role = html.escape((role or "").strip() or "dentist")
    safe_clinic = html.escape((clinic_name or "").strip() or "N/A")
    safe_phone = html.escape((phone or "").strip() or "N/A")
    details = (
        f"<strong>Name:</strong> {safe_name}<br>"
        f"<strong>E-Mail:</strong> {safe_email}<br>"
        f"<strong>Rolle / Role:</strong> {safe_role}<br>"
        f"<strong>Praxis / Clinic:</strong> {safe_clinic}<br>"
        f"<strong>Telefon / Phone:</strong> {safe_phone}"
    )
    return _branded_html(
        title=("Neue Registrierung", "New user signup"),
        intro=(
            "Es gibt eine neue Registrierung bei Elite Dent. Bitte melden Sie sich an, um das Konto zu verifizieren.",
            "There is a new user signup to Elite Dent. Please sign in to verify the account.",
        ),
        details_html=details,
        footer=(
            "Diese Benachrichtigung wurde an das Administrator-Postfach gesendet.",
            "This alert was sent to the administrator inbox.",
        ),
    )


def _send_resend(*, to_email: str, subject: str, html_body: str) -> None:
    api_key = (settings.resend_api_key or "").strip()
    if not api_key:
        logger.warning("RESEND_API_KEY missing — skipping email subject=%s", subject)
        return
    to = (to_email or "").strip()
    if not to:
        logger.warning("Empty recipient — skipping email subject=%s", subject)
        return

    resend.api_key = api_key
    try:
        resend.Emails.send(
            {
                "from": _from_address(),
                "to": [to],
                "subject": subject,
                "html": html_body,
            }
        )
    except Exception as exc:
        logger.exception("Failed to send email via Resend subject=%s: %s", subject, exc)


def send_welcome_email(
    name: str,
    email: str = "",
    role: str = "dentist",
    clinic_name: str | None = None,
    phone: str | None = None,
) -> None:
    """Signup: notify the new user and the admin inbox. Safe for BackgroundTasks."""
    user_email = (email or "").strip()
    display = (name or "").strip() or "Hallo"
    if user_email:
        _send_resend(
            to_email=user_email,
            subject="Ihr Elite Dent Konto wird geprüft / Your Elite Dent account is pending verification",
            html_body=_branded_html(
                title=("Konto erhalten", "Account received"),
                intro=(
                    f"Guten Tag {display}, vielen Dank für Ihre Registrierung bei Elite Dent. "
                    "Ein Administrator muss Ihr Konto prüfen, bevor Sie sich anmelden können. "
                    "Sie erhalten eine weitere E-Mail, sobald der Zugang freigegeben ist.",
                    f"Hello {display}, thank you for registering with Elite Dent. "
                    "An administrator must verify your account before you can sign in. "
                    "You will receive another email once access is approved.",
                ),
                footer=(
                    "Falls Sie dieses Konto nicht erstellt haben, können Sie diese E-Mail ignorieren.",
                    "If you did not create this account, you can ignore this email.",
                ),
            ),
        )
    _send_resend(
        to_email=_admin_inbox(),
        subject="Neue Registrierung / New user signup — Elite Dent",
        html_body=_signup_notify_html(
            name=name,
            email=email,
            role=role,
            clinic_name=clinic_name,
            phone=phone,
        ),
    )


def send_account_verified_email(name: str, email: str) -> None:
    """Tell the user they can sign in after admin verification."""
    display = (name or "").strip() or "Hallo"
    _send_resend(
        to_email=email,
        subject="Ihr Elite Dent Konto ist freigegeben / Your Elite Dent account is approved",
        html_body=_branded_html(
            title=("Sie können sich jetzt anmelden", "You can sign in now"),
            intro=(
                f"Guten Tag {display}, ein Administrator hat Ihr Elite Dent Konto verifiziert. "
                "Sie können sich mit der bei der Registrierung verwendeten E-Mail-Adresse und dem Passwort anmelden.",
                f"Hello {display}, an administrator has verified your Elite Dent account. "
                "You can sign in with the email and password you registered.",
            ),
            footer=(
                "Bei Fragen wenden Sie sich an support@elite-d.de.",
                "If you need help, contact support@elite-d.de.",
            ),
        ),
    )


def send_signup_rejected_email(name: str, email: str, reason: str | None = None) -> None:
    """Tell a signup the admin declined it, with the reason when one was given."""
    display = (name or "").strip() or "Hallo"
    reason = (reason or "").strip()
    intro_de = f"Guten Tag {display}, Ihre Registrierung bei Elite Dent wurde nicht genehmigt."
    intro_en = f"Hello {display}, your Elite Dent registration was not approved."
    if reason:
        intro_de += f" Grund: {reason}"
        intro_en += f" Reason: {reason}"
    _send_resend(
        to_email=email,
        subject="Ihre Elite Dent Registrierung / Your Elite Dent registration",
        html_body=_branded_html(
            title=("Registrierung nicht genehmigt", "Registration not approved"),
            intro=(intro_de, intro_en),
            footer=(
                "Falls Sie dies für einen Irrtum halten, wenden Sie sich an support@elite-d.de.",
                "If you think this is a mistake, contact support@elite-d.de.",
            ),
        ),
    )


def send_account_deleted_email(name: str, email: str) -> None:
    """Confirm self-service account deletion."""
    display = (name or "").strip() or "Hallo"
    _send_resend(
        to_email=email,
        subject="Ihr Elite Dent Konto wurde gelöscht / Your Elite Dent account has been deleted",
        html_body=_branded_html(
            title=("Konto gelöscht", "Account deleted"),
            intro=(
                f"Guten Tag {display}, Ihr Elite Dent Konto und die zugehörigen klinischen Daten "
                "wurden auf Ihren Wunsch endgültig entfernt.",
                f"Hello {display}, your Elite Dent account and associated clinical data "
                "have been permanently removed as requested.",
            ),
            footer=(
                "Falls Sie dies nicht veranlasst haben, kontaktieren Sie umgehend support@elite-d.de.",
                "If you did not request this, contact support@elite-d.de immediately.",
            ),
        ),
    )


def send_appointment_confirmation(
    patient_email: str,
    patient_name: str,
    start_time: datetime | str,
    end_time: datetime | str,
    description: str | None = None,
) -> None:
    """Email the patient a new appointment confirmation. Safe for BackgroundTasks."""
    name = (patient_name or "").strip() or "Patient"
    desc = (description or "").strip() or "Klinischer Termin / Clinical visit"
    window = _format_visit_window(start_time, end_time)
    details = (
        f"<strong>Patient:</strong> {html.escape(name)}<br>"
        f"<strong>Wann / When:</strong> {html.escape(window)}<br>"
        f"<strong>Details:</strong> {html.escape(desc)}"
    )
    html_body = _appointment_email_shell(
        title=("Termin bestätigt", "Appointment confirmed"),
        intro=(
            f"Guten Tag {name}, Ihr Termin bei Elite Dent wurde vereinbart. Die Details finden Sie unten.",
            f"Hello {name}, your visit with Elite Dent has been scheduled. Please find the details below.",
        ),
        details_html=details,
    )
    _send_resend(
        to_email=patient_email,
        subject="Ihr Elite Dent Termin ist bestätigt / Your Elite Dent appointment is confirmed",
        html_body=html_body,
    )


def send_appointment_update(
    patient_email: str,
    patient_name: str,
    start_time: datetime | str,
    end_time: datetime | str,
    status: str,
    description: str | None = None,
) -> None:
    """Email the patient an appointment schedule/status update. Safe for BackgroundTasks."""
    name = (patient_name or "").strip() or "Patient"
    desc = (description or "").strip() or "Klinischer Termin / Clinical visit"
    key = status or "scheduled"
    status_label = _STATUS_LABELS.get(key) or key.replace("_", " ").title()
    window = _format_visit_window(start_time, end_time)
    details = (
        f"<strong>Patient:</strong> {html.escape(name)}<br>"
        f"<strong>Status:</strong> {html.escape(status_label)}<br>"
        f"<strong>Wann / When:</strong> {html.escape(window)}<br>"
        f"<strong>Details:</strong> {html.escape(desc)}"
    )
    html_body = _appointment_email_shell(
        title=("Termin geändert", "Appointment updated"),
        intro=(
            f"Guten Tag {name}, Ihr Elite Dent Termin wurde geändert. Bitte prüfen Sie die aktuellen Details.",
            f"Hello {name}, your Elite Dent appointment has been updated. Please review the latest visit details.",
        ),
        details_html=details,
    )
    _send_resend(
        to_email=patient_email,
        subject=f"Elite Dent Termin geändert / appointment update — {status_label}",
        html_body=html_body,
    )


def send_appointment_cancelled(
    patient_email: str,
    patient_name: str,
    start_time: datetime | str,
    end_time: datetime | str,
    description: str | None = None,
) -> None:
    """Email the patient when an appointment is deleted. Safe for BackgroundTasks."""
    name = (patient_name or "").strip() or "Patient"
    desc = (description or "").strip() or "Klinischer Termin / Clinical visit"
    window = _format_visit_window(start_time, end_time)
    details = (
        f"<strong>Patient:</strong> {html.escape(name)}<br>"
        f"<strong>Wann / When:</strong> {html.escape(window)}<br>"
        f"<strong>Details:</strong> {html.escape(desc)}"
    )
    html_body = _appointment_email_shell(
        title=("Termin abgesagt", "Appointment cancelled"),
        intro=(
            f"Guten Tag {name}, Ihr Elite Dent Termin wurde abgesagt. Bitte wenden Sie sich an Ihre Praxis, wenn Sie einen neuen Termin benötigen.",
            f"Hello {name}, your Elite Dent appointment has been cancelled. Please contact your clinic if you need a new time.",
        ),
        details_html=details,
    )
    _send_resend(
        to_email=patient_email,
        subject="Ihr Elite Dent Termin wurde abgesagt / Your Elite Dent appointment was cancelled",
        html_body=html_body,
    )
