from fastapi import APIRouter, Depends

from .auth import get_current_user
from .models import load_destinations

router = APIRouter()


@router.get("/recommendations")
def get_recommendations(current_user: dict = Depends(get_current_user)):
    destinations = load_destinations()
    prefs = current_user.get("preferences", [])
    if prefs:
        matches = [d for d in destinations if any(tag in prefs for tag in d["tags"])]
        if matches:
            return matches
    return destinations[:3]
