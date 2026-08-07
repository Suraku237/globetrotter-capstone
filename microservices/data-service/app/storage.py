"""
Firebase Storage upload helper, used to host post media (photos/videos)
on Google's CDN instead of this container's local disk — so posts survive
container rebuilds/host migrations and video streams reliably (byte-range
requests work, unlike Google Drive's share links).

Setup required (one-time, on the server):
Reuses the same service account file as auth-service — see
auth-service/app/firebase_auth.py for how to obtain it.
1. Firebase Console -> Project Settings -> Service Accounts -> Generate new private key
2. Save the downloaded JSON as microservices/firebase-service-account.json
   (gitignored — never commit it, it's a real credential)
3. Set FIREBASE_CREDENTIALS_PATH in data-service/.env if you use a different path/name
4. Set FIREBASE_STORAGE_BUCKET if your bucket isn't the project's default
"""

import mimetypes
import os
import uuid
from pathlib import Path
from typing import Optional

import firebase_admin
from firebase_admin import credentials, storage

_SERVICE_DIR = Path(__file__).resolve().parent.parent
_DEFAULT_CRED_PATH = _SERVICE_DIR / "firebase-service-account.json"
_DEFAULT_BUCKET = "fast-travel-cbd10.firebasestorage.app"

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

    bucket_name = os.getenv("FIREBASE_STORAGE_BUCKET", _DEFAULT_BUCKET)
    cred = credentials.Certificate(cred_path)
    _firebase_app = firebase_admin.initialize_app(
        cred, {"storageBucket": bucket_name}
    )
    return _firebase_app


def upload_post_media(contents: bytes, filename: str, content_type: Optional[str]) -> str:
    """Uploads raw bytes to Firebase Storage under posts/ and returns a public URL."""
    app = _get_firebase_app()
    bucket = storage.bucket(app=app)
    extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    blob_name = f"posts/{uuid.uuid4().hex}.{extension}" if extension else f"posts/{uuid.uuid4().hex}"
    # Browsers refuse to play video/render images served as
    # application/octet-stream, so fall back to guessing from the filename
    # whenever the multipart upload didn't carry a specific content type.
    if not content_type or content_type == "application/octet-stream":
        content_type = mimetypes.guess_type(filename)[0] or content_type
    blob = bucket.blob(blob_name)
    blob.upload_from_string(contents, content_type=content_type)
    blob.make_public()
    return blob.public_url
