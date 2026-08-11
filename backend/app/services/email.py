"""Transactional email helpers (Resend)."""

from __future__ import annotations

import html
import logging
from datetime import datetime

import resend

from app.core.config import settings

logger = logging.getLogger(__name__)


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


def _appointment_email_shell(*, title: str, intro: str, details_html: str) -> str:
    safe_title = html.escape(title)
    safe_intro = html.escape(intro)
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
              </td>
            </tr>
            <tr>
              <td style="padding:32px;">
                <p style="margin:0 0 20px;font-size:16px;line-height:1.65;font-family:Arial,Helvetica,sans-serif;color:#334155;">
                  {safe_intro}
                </p>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 24px;background:#f7faf9;border:1px solid #e2ebe8;border-radius:4px;">
                  <tr>
                    <td style="padding:18px 20px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.7;color:#1a2e2a;">
                      {details_html}
                    </td>
                  </tr>
                </table>
                <p style="margin:0;font-size:13px;line-height:1.5;color:#64748b;font-family:Arial,Helvetica,sans-serif;">
                  If you need to reschedule, please contact your clinic.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 32px 28px;border-top:1px solid #eef2f1;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#94a3b8;">
                — Elite Dent Clinical Scheduling
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>"""


def _signup_notify_html(
    *,
    name: str,
    email: str,
    role: str = "clinic",
    clinic_name: str | None = None,
    phone: str | None = None,
) -> str:
    safe_name = html.escape((name or "").strip() or "N/A")
    safe_email = html.escape((email or "").strip() or "N/A")
    safe_role = html.escape((role or "").strip() or "clinic")
    safe_clinic = html.escape((clinic_name or "").strip() or "N/A")
    safe_phone = html.escape((phone or "").strip() or "N/A")

    return f"""<!DOCTYPE html>
<html>
  <body style="margin:0;padding:0;background:#f5f7fb;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border-radius:12px;padding:32px;border:1px solid #e5e7eb;">
            <tr>
              <td>
                <h1 style="margin:0 0 12px;font-size:24px;line-height:1.3;">New user signup</h1>
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;">
                  There is a new user signup to your dental app. Please login to verify the new user.
                </p>
                <p style="margin:0 0 8px;font-size:16px;line-height:1.6;font-weight:bold;">
                  User details:
                </p>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 24px;font-size:15px;line-height:1.7;background:#f9fafb;border-radius:8px;border:1px solid #e5e7eb;">
                  <tr><td style="padding:12px 16px;">
                    <strong>Name:</strong> {safe_name}<br>
                    <strong>Email:</strong> {safe_email}<br>
                    <strong>Role:</strong> {safe_role}<br>
                    <strong>Clinic:</strong> {safe_clinic}<br>
                    <strong>Phone:</strong> {safe_phone}
                  </td></tr>
                </table>
                <p style="margin:0;font-size:14px;line-height:1.5;color:#6b7280;">
                  — Dental Lab AI
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>"""


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
                "from": settings.resend_from_email,
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
    role: str = "clinic",
    clinic_name: str | None = None,
    phone: str | None = None,
) -> None:
    """Notify admin of a successful signup. Safe to run in BackgroundTasks."""
    api_key = (settings.resend_api_key or "").strip()
    if not api_key:
        logger.warning("RESEND_API_KEY missing — skipping signup notification email")
        return

    resend.api_key = api_key
    try:
        resend.Emails.send(
            {
                "from": settings.resend_from_email,
                "to": [settings.resend_welcome_to_email],
                "subject": "New user signup — Dental Lab AI",
                "html": _signup_notify_html(
                    name=name,
                    email=email,
                    role=role,
                    clinic_name=clinic_name,
                    phone=phone,
                ),
            }
        )
    except Exception as exc:
        logger.exception(
            "Failed to send signup notification email via Resend: %s", exc
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
    desc = (description or "").strip() or "Clinical visit"
    window = _format_visit_window(start_time, end_time)
    details = (
        f"<strong>Patient:</strong> {html.escape(name)}<br>"
        f"<strong>When:</strong> {html.escape(window)}<br>"
        f"<strong>Details:</strong> {html.escape(desc)}"
    )
    html_body = _appointment_email_shell(
        title="Appointment confirmed",
        intro=(
            f"Hello {name}, your visit with Elite Dent has been scheduled. "
            "Please find the details below."
        ),
        details_html=details,
    )
    _send_resend(
        to_email=patient_email,
        subject="Your Elite Dent appointment is confirmed",
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
    desc = (description or "").strip() or "Clinical visit"
    status_label = (status or "scheduled").replace("_", " ").title()
    window = _format_visit_window(start_time, end_time)
    details = (
        f"<strong>Patient:</strong> {html.escape(name)}<br>"
        f"<strong>Status:</strong> {html.escape(status_label)}<br>"
        f"<strong>When:</strong> {html.escape(window)}<br>"
        f"<strong>Details:</strong> {html.escape(desc)}"
    )
    html_body = _appointment_email_shell(
        title="Appointment updated",
        intro=(
            f"Hello {name}, your Elite Dent appointment has been updated. "
            "Please review the latest visit details."
        ),
        details_html=details,
    )
    _send_resend(
        to_email=patient_email,
        subject=f"Elite Dent appointment update — {status_label}",
        html_body=html_body,
    )
