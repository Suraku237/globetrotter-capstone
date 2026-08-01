from typing import Optional, List, Dict, Any

from fastapi import APIRouter

from .models import load_destinations

router = APIRouter()


@router.get("/destinations")
def get_destinations(q: Optional[str] = None) -> List[Dict[str, Any]]:
    # 1. Load the data
    data = load_destinations()
    
    # 2. YOUR JSON has a wrapper "destinations". Extract the actual list.
    destinations = data.get("destinations", [])  
    
    # 3. Handle search query
    if q:
        q_lower = q.lower()
        destinations = [
            d
            for d in destinations
            if q_lower in d["name"].lower()
            or q_lower in d["region"].lower()
            or any(q_lower in tag for tag in d["tags"])
        ]

    # 4. 👇 FIX THE IMAGE URLS HERE 👇
    for dest in destinations:
        # Your JSON uses an ARRAY called "images", not a string called "image"
        if "images" in dest and isinstance(dest["images"], list):
            # Change "/images/destinations/dest_001.jpg" to "/images/dest_001.jpg"
            # (Removes the extra "destinations" folder from the path so it matches your mount)
            dest["images"] = [
                img.replace("/images/destinations/", "/images/") 
                for img in dest["images"]
            ]
            
            # (Optional) If you want to flatten it to a single string for Flutter:
            # dest["image"] = dest["images"][0] if dest["images"] else ""

    return destinations