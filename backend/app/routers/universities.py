from fastapi import APIRouter
from pydantic import BaseModel
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

@router.get("/")
def get_universities(user_id: str):
    db = get_supabase()
    response = db.table("uni_applications").select("*").eq("user_id", user_id).execute()
    return response.data

@router.post("/")
def add_university(uni: UniApplication):
    db = get_supabase()
    response = db.table("uni_applications").insert(uni.dict()).execute()
    return response.data

@router.patch("/{uni_id}")
def update_university(uni_id: str, updates: dict):
    db = get_supabase()
    response = db.table("uni_applications").update(updates).eq("id", uni_id).execute()
    return response.data

@router.delete("/{uni_id}")
def delete_university(uni_id: str):
    db = get_supabase()
    db.table("uni_applications").delete().eq("id", uni_id).execute()
    return {"message": "Deleted"}
