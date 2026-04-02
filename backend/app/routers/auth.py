from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.database import get_supabase

router = APIRouter()

class UserProfile(BaseModel):
    user_id: str
    full_name: str
    email: str
    phone: str = ""
    linkedin_url: str = ""
    skills: list[str] = []
    education: list[dict] = []
    experience: list[dict] = []
    summary: str = ""

@router.post("/profile")
def create_profile(profile: UserProfile):
    db = get_supabase()
    response = db.table("user_profiles").upsert(profile.dict()).execute()
    return response.data

@router.get("/profile/{user_id}")
def get_profile(user_id: str):
    db = get_supabase()
    response = db.table("user_profiles").select("*").eq("user_id", user_id).single().execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return response.data
