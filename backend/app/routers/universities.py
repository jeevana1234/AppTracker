from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.database import get_supabase

router = APIRouter()

class UniApplication(BaseModel):
    university: str
    program: str
    degree: str = "Masters"       # Masters | PhD | Bachelors
    status: str = "preparing"     # preparing | submitted | interview | accepted | rejected
    deadline: str = ""
    portal_url: str = ""
    notes: str = ""
    user_id: str

class UniApplicationUpdate(BaseModel):
    university: Optional[str] = None
    program: Optional[str] = None
    degree: Optional[str] = None
    status: Optional[str] = None
    deadline: Optional[str] = None
    portal_url: Optional[str] = None
    notes: Optional[str] = None

@router.get("/")
def get_universities(user_id: str):
    db = get_supabase()
    response = db.table("uni_applications").select("*").eq("user_id", user_id).execute()
    return response.data

@router.post("/")
def add_university(uni: UniApplication):
    db = get_supabase()
    response = db.table("uni_applications").insert(uni.model_dump()).execute()
    return response.data

@router.patch("/{uni_id}")
def update_university(uni_id: str, updates: UniApplicationUpdate):
    db = get_supabase()
    data = {k: v for k, v in updates.model_dump().items() if v is not None}
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")
    response = db.table("uni_applications").update(data).eq("id", uni_id).execute()
    return response.data

@router.delete("/{uni_id}")
def delete_university(uni_id: str):
    db = get_supabase()
    db.table("uni_applications").delete().eq("id", uni_id).execute()
    return {"message": "Deleted"}
