from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel, EmailStr
from typing import Optional
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
    resume_url: str = ""

class UserProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    linkedin_url: Optional[str] = None
    skills: Optional[list[str]] = None
    education: Optional[list[dict]] = None
    experience: Optional[list[dict]] = None
    summary: Optional[str] = None

@router.post("/profile")
def create_profile(profile: UserProfile):
    db = get_supabase()
    response = db.table("user_profiles").upsert(profile.model_dump()).execute()
    return response.data

@router.get("/profile/{user_id}")
def get_profile(user_id: str):
    db = get_supabase()
    response = db.table("user_profiles").select("*").eq("user_id", user_id).single().execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return response.data

@router.patch("/profile/{user_id}")
def update_profile(user_id: str, updates: UserProfileUpdate):
    db = get_supabase()
    # Only send fields that were actually provided
    data = {k: v for k, v in updates.model_dump().items() if v is not None}
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")
    response = db.table("user_profiles").update(data).eq("user_id", user_id).execute()
    return response.data
