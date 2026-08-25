import unittest
from unittest.mock import patch

from app.services import email as email_svc


class EmailServiceTests(unittest.TestCase):
    @patch("app.services.email.resend.Emails.send")
    @patch("app.services.email.settings")
    def test_signup_emails_user_and_admin(self, mock_settings, mock_send):
        mock_settings.resend_api_key = "re_test"
        mock_settings.resend_from_email = (
            "Elite Dental Support <support@elite-d.de>"
        )
        mock_settings.resend_welcome_to_email = "ops@elite-d.de"

        email_svc.send_welcome_email(
            "Ada", "ada@clinic.de", "dentist", "Clinic", "+49111111111"
        )

        self.assertEqual(mock_send.call_count, 2)
        payloads = [c.args[0] for c in mock_send.call_args_list]
        recipients = {p["to"][0] for p in payloads}
        self.assertEqual(recipients, {"ada@clinic.de", "ops@elite-d.de"})
        self.assertEqual(
            {p["from"] for p in payloads},
            {"Elite Dental Support <support@elite-d.de>"},
        )
        self.assertNotIn("onboarding@resend.dev", str(payloads))

    @patch("app.services.email.resend.Emails.send")
    @patch("app.services.email.settings")
    def test_test_domain_from_address_is_replaced(
        self, mock_settings, mock_send
    ):
        mock_settings.resend_api_key = "re_test"
        mock_settings.resend_from_email = "onboarding@resend.dev"
        mock_settings.resend_welcome_to_email = "onboarding@resend.dev"

        email_svc.send_account_verified_email("Ada", "ada@clinic.de")

        payload = mock_send.call_args.args[0]
        self.assertEqual(payload["from"], email_svc._DEFAULT_FROM)
        self.assertEqual(payload["to"], ["ada@clinic.de"])
        self.assertNotIn("onboarding@resend.dev", payload["from"])

    @patch("app.services.email.resend.Emails.send")
    @patch("app.services.email.settings")
    def test_resend_failure_does_not_raise(self, mock_settings, mock_send):
        mock_settings.resend_api_key = "re_test"
        mock_settings.resend_from_email = (
            "Elite Dental Support <support@elite-d.de>"
        )
        mock_settings.resend_welcome_to_email = "support@elite-d.de"
        mock_send.side_effect = RuntimeError("resend down")

        email_svc.send_welcome_email("Ada", "ada@clinic.de")
        email_svc.send_appointment_confirmation(
            "p@clinic.de",
            "Pat",
            "2026-08-25T10:00:00Z",
            "2026-08-25T10:30:00Z",
        )
        email_svc.send_appointment_cancelled(
            "p@clinic.de",
            "Pat",
            "2026-08-25T10:00:00Z",
            "2026-08-25T10:30:00Z",
        )
        email_svc.send_account_deleted_email("Ada", "ada@clinic.de")


if __name__ == "__main__":
    unittest.main()
