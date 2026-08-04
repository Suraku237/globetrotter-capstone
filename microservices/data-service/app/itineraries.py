import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from .security import get_current_user
from .models import ItineraryCreate, load_itineraries, save_itineraries

router = APIRouter()


@router.post("/itineraries", status_code=201)
def create_itinerary(payload: ItineraryCreate, current_user: dict = Depends(get_current_user)):
    itineraries = load_itineraries()
    itinerary = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "title": payload.title,
        "destination_id": payload.destination_id,
        "start_date": payload.start_date,
        "end_date": payload.end_date,
        "notes": payload.notes,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    itineraries.append(itinerary)
    save_itineraries(itineraries)
    return itinerary


@router.get("/itineraries")
def get_itineraries(current_user: dict = Depends(get_current_user)):
    itineraries = load_itineraries()
    return [i for i in itineraries if i["user_id"] == current_user["id"]]
