from typing import Optional, List, Dict, Any

from fastapi import APIRouter

from .models import load_destinations

router = APIRouter()


@router.get("/destinations")
def get_destinations(q: Optional[str] = None) -> List[Dict[str, Any]]:
    destinations = load_destinations()

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
