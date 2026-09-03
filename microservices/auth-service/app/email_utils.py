"""
Transactional email via Brevo's SMTP relay — used for the two flows that
need a human to receive mail:
  1. New regular-user signups get a 6-digit code to prove the email address
     they entered is real, before their account can log in.
  2. New admin *and* worker signups don't self-activate at all — a request
     goes to SUPER_ADMIN_EMAIL with an approve/reject link, and the
     requester only gets in once that's clicked.
"""

import logging
import secrets
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from fastapi import HTTPException

from .models import (
    BREVO_SENDER_EMAIL,
    BREVO_SMTP_LOGIN,
    BREVO_SMTP_PASSWORD,
    PUBLIC_API_BASE_URL,
    SUPER_ADMIN_EMAIL,
)

logger = logging.getLogger(__name__)

SMTP_HOST = "smtp-relay.brevo.com"
SMTP_PORT = 587


def generate_verification_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def generate_approval_token() -> str:
    return secrets.token_urlsafe(32)


def _send(to_email: str, subject: str, html_body: str) -> None:
    if not (BREVO_SMTP_LOGIN and BREVO_SMTP_PASSWORD and BREVO_SENDER_EMAIL):
        raise HTTPException(
            status_code=503,
            detail=(
                "Email isn't configured yet (missing BREVO_SMTP_LOGIN / "
                "BREVO_SMTP_PASSWORD / BREVO_SENDER_EMAIL)."
            ),
        )

    message = MIMEMultipart("alternative")
    message["Subject"] = subject
    message["From"] = f"Fast Travel <{BREVO_SENDER_EMAIL}>"
    message["To"] = to_email
    message.attach(MIMEText(html_body, "html"))

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
            server.starttls()
            server.login(BREVO_SMTP_LOGIN, BREVO_SMTP_PASSWORD)
            server.sendmail(BREVO_SENDER_EMAIL, [to_email], message.as_string())
    except (smtplib.SMTPException, OSError) as exc:
        # OSError covers connection-level failures (timeout, connection
        # refused, DNS) that smtplib.SMTPException doesn't — e.g. a VPS
        # provider blocking outbound port 587 makes the connect() call
        # raise socket.timeout, which isn't an SMTPException subclass.
        logger.error("Failed to send email to %s: %s", to_email, exc)
        raise HTTPException(
            status_code=502,
            detail="Could not send the email right now. Try again shortly.",
        ) from exc


def send_verification_code_email(to_email: str, full_name: str, code: str) -> None:
    _send(
        to_email,
        "Verify your Fast Travel account",
        f"""
        <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
          <h2 style="color:#171932;">Welcome to Fast Travel, {full_name}!</h2>
          <p>Enter this code in the app to verify your email and finish creating your account:</p>
          <p style="font-size: 32px; font-weight: bold; letter-spacing: 8px;
                    background:#FAF9F6; padding: 16px 24px; border-radius: 12px;
                    text-align:center; color:#FF6A4D;">{code}</p>
          <p>This code expires in 15 minutes. If you didn't request this, you can ignore this email.</p>
        </div>
        """,
    )


def send_admin_approval_request_email(
    requester_id: str,
    requester_email: str,
    requester_name: str,
    token: str,
    role: str = "admin",
) -> None:
    if not SUPER_ADMIN_EMAIL:
        raise HTTPException(
            status_code=503,
            detail="Admin approval email isn't configured yet (missing SUPER_ADMIN_EMAIL).",
        )
    approve_url = (
        f"{PUBLIC_API_BASE_URL}/admin-requests/{requester_id}/approve?token={token}"
    )
    reject_url = (
        f"{PUBLIC_API_BASE_URL}/admin-requests/{requester_id}/reject?token={token}"
    )
    role_label = "worker" if role == "worker" else "admin"
    _send(
        SUPER_ADMIN_EMAIL,
        f"New {role_label} account request — Fast Travel",
        f"""
        <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
          <h2 style="color:#171932;">New {role_label} request</h2>
          <p><strong>{requester_name}</strong> ({requester_email}) has requested a <strong>{role_label}</strong> account.</p>
          <p style="margin-top:24px;">
            <a href="{approve_url}"
               style="background:#FF6A4D; color:white; padding:12px 24px; border-radius:24px;
                      text-decoration:none; font-weight:bold; margin-right:12px;">Approve</a>
            <a href="{reject_url}"
               style="background:#E5E5E5; color:#171932; padding:12px 24px; border-radius:24px;
                      text-decoration:none; font-weight:bold;">Reject</a>
          </p>
          <p style="margin-top:20px; font-size:12px; color:#6B7280;">
            If a button above doesn't work (e.g. your email provider's
            click-tracking mangles it), use one of these plain-text links
            instead:<br>
            Approve: {approve_url}<br>
            Reject: {reject_url}
          </p>
        </div>
        """,
    )


def send_admin_admission_email(
    to_email: str, full_name: str, role: str = "admin"
) -> None:
    role_label = "worker" if role == "worker" else "admin"
    _send(
        to_email,
        f"You're approved as a Fast Travel {role_label}",
        f"""
        <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
          <h2 style="color:#171932;">Congratulations, {full_name}!</h2>
          <p>Your Fast Travel {role_label} account has been approved. You can now sign in with the
             email and password you registered with.</p>
        </div>
        """,
    )


def send_admin_rejection_email(
    to_email: str, full_name: str, role: str = "admin"
) -> None:
    role_label = "worker" if role == "worker" else "admin"
    _send(
        to_email,
        f"Your Fast Travel {role_label} request",
        f"""
        <div style="font-family: sans-serif; max-width: 480px; margin: auto;">
          <h2 style="color:#171932;">Hi {full_name},</h2>
          <p>Your request for a {role_label} account on Fast Travel was not approved at this time.</p>
        </div>
        """,
    )
