"""Transactional email helpers (Resend)."""

from __future__ import annotations

import html
import logging

import resend

from app.core.config import settings

logger = logging.getLogger(__name__)


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
    except Exception:
        logger.exception("Failed to send signup notification email via Resend")
