from typing import Optional, List, Dict, Any

from fastapi import APIRouter

from .models import load_destinations

router = APIRouter()


@router.get("/destinations")
def get_destinations(q: Optional[str] = None) -> List[Dict[str, Any]]:
    destinations = load_destinations()
    
    # 1. Handle search query (your existing filter logic)
    if q:
        q_lower = q.lower()
        destinations = [
            d
            for d in destinations
            if q_lower in d["name"].lower()
            or q_lower in d["region"].lower()
            or any(q_lower in tag for tag in d["tags"])
        ]

    # 2. 👇 FIX THE IMAGE URLS HERE 👇
    # This ensures Flutter gets a full URL path to the image
    for dest in destinations:
        if "image" in dest and dest["image"]:
            # If the JSON has "dest_001.jpg", change it to "/images/dest_001.jpg"
            # This matches the static mount we set up in __init__.py
            if not dest["image"].startswith("/"):
                dest["image"] = f"/images/{dest['image']}"

    return destinations