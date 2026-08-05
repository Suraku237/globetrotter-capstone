import uuid
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from .models import DATA_DIR, load_destinations, save_destinations
from .security import get_current_user, require_worker_or_admin

router = APIRouter()

IMAGES_DIR = DATA_DIR / "images"


@router.get("/destinations")
def get_destinations(q: Optional[str] = None) -> List[Dict[str, Any]]:
    destinations = [
        d for d in load_destinations() if d.get("status", "approved") == "approved"
    ]

    if q:
        q_lower = q.lower()
        destinations = [
            d
            for d in destinations
            if q_lower in d["name"].lower()
            or q_lower in d["region"].lower()
            or any(q_lower in tag for tag in d["tags"])
        ]

    return destinations


@router.get("/destinations/pending")
def get_pending_destinations(
    current_user: dict = Depends(require_worker_or_admin),
) -> List[Dict[str, Any]]:
    return [d for d in load_destinations() if d.get("status") == "pending"]


@router.post("/destinations", status_code=201)
async def suggest_destination(
    name: str = Form(...),
    description: str = Form(...),
    lat: float = Form(...),
    lng: float = Form(...),
    region: str = Form("Unknown"),
    image: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    new_id = f"dest_{uuid.uuid4().hex[:10]}"
    extension = (image.filename or "").rsplit(".", 1)[-1].lower() or "jpg"
    filename = f"{new_id}.{extension}"
    contents = await image.read()
    with open(IMAGES_DIR / filename, "wb") as f:
        f.write(contents)

    destinations = load_destinations()
    entry = {
        "id": new_id,
        "name": name,
        "region": region,
        "tags": [],
        "images": [f"/images/{filename}"],
        "description": description,
        "lat": lat,
        "lng": lng,
        "status": "pending",
        "submitted_by": current_user["id"],
    }
    destinations.append(entry)
    save_destinations(destinations)
    return entry


@router.post("/destinations/{destination_id}/approve")
def approve_destination(
    destination_id: str,
    current_user: dict = Depends(require_worker_or_admin),
):
    destinations = load_destinations()
    entry = next((d for d in destinations if d["id"] == destination_id), None)
    if entry is None:
        raise HTTPException(status_code=404, detail="Destination not found")
    entry["status"] = "approved"
    save_destinations(destinations)
    return entry


@router.post("/destinations/{destination_id}/reject")
def reject_destination(
    destination_id: str,
    current_user: dict = Depends(require_worker_or_admin),
):
    destinations = load_destinations()
    entry = next((d for d in destinations if d["id"] == destination_id), None)
    if entry is None:
        raise HTTPException(status_code=404, detail="Destination not found")
    entry["status"] = "rejected"
    save_destinations(destinations)
    return entry
