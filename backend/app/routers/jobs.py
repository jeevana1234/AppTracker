from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.database import get_supabase

router = APIRouter()

class JobApplication(BaseModel):
    company: str
    role: str
    status: str = "applied"       # applied | interview | offer | rejected
    job_url: str = ""
    notes: str = ""
    user_id: str

class JobApplicationUpdate(BaseModel):
    company: Optional[str] = None
    role: Optional[str] = None
    status: Optional[str] = None
    job_url: Optional[str] = None
    notes: Optional[str] = None

@router.get("/")
def get_jobs(user_id: str):
    db = get_supabase()
    response = db.table("job_applications").select("*").eq("user_id", user_id).execute()
    return response.data

@router.post("/")
def add_job(job: JobApplication):
    db = get_supabase()
    response = db.table("job_applications").insert(job.model_dump()).execute()
    return response.data

@router.patch("/{job_id}")
def update_job(job_id: str, updates: JobApplicationUpdate):
    db = get_supabase()
    data = {k: v for k, v in updates.model_dump().items() if v is not None}
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")
    response = db.table("job_applications").update(data).eq("id", job_id).execute()
    return response.data

@router.delete("/{job_id}")
def delete_job(job_id: str):
    db = get_supabase()
    db.table("job_applications").delete().eq("id", job_id).execute()
    return {"message": "Deleted"}
