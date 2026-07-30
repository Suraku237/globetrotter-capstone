"""
Firebase Admin SDK setup, used to verify Google/Facebook sign-in tokens
sent from the Flutter app.

How this fits in:
The Flutter app signs the user in with Firebase Auth (Google or Facebook
provider) and gets back a Firebase ID token. It sends that token here.
We verify it's genuinely issued by Firebase for OUR project (not forged),
extract the user's email/name, then find-or-create a normal user record
and issue our own JWT — so the rest of the app (itineraries, recommendations,
etc.) keeps working exactly as before, unaware Google/Facebook was involved.

Setup required (one-time, on the server):
1. Firebase Console -> Project Settings -> Service Accounts -> Generate new private key
2. Save the downloaded JSON as backend/firebase-service-account.json
   (this file is gitignored — never commit it, it's a real credential)
3. Set FIREBASE_CREDENTIALS_PATH in backend/.env if you use a different path/name
"""

import os
from pathlib import Path

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from fastapi import HTTPException

_BACKEND_DIR = Path(__file__).resolve().parent.parent
_DEFAULT_CRED_PATH = _BACKEND_DIR / "firebase-service-account.json"

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", str(_DEFAULT_CRED_PATH))
    if not Path(cred_path).exists():
        raise RuntimeError(
            f"Firebase service account file not found at {cred_path}. "
            "Download it from Firebase Console > Project Settings > Service Accounts."
        )

    cred = credentials.Certificate(cred_path)
    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def verify_firebase_token(id_token: str) -> dict:
    """
    Verifies a Firebase ID token and returns the decoded claims
    (includes at least: uid, email, name, picture if available).
    Raises HTTPException(401) if the token is invalid/expired.
    """
    _get_firebase_app()
    try:
        decoded = firebase_auth.verify_id_token(id_token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc
    return decoded