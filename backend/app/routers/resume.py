from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.resume_service import generate_resume_pdf
from app.database import get_supabase

router = APIRouter()

class ResumeRequest(BaseModel):
    user_id: str
    job_description: str = ""   # optional: tailor resume to a job

@router.post("/generate")
async def generate_resume(request: ResumeRequest):
    db = get_supabase()
    # Fetch user profile from Supabase
    profile = db.table("user_profiles").select("*").eq("user_id", request.user_id).single().execute()
    if not profile.data:
        raise HTTPException(status_code=404, detail="User profile not found")

    pdf_url = await generate_resume_pdf(profile.data, request.job_description)
    return {"pdf_url": pdf_url, "message": "Resume generated successfully"}

@router.get("/download/{user_id}")
def get_resume_url(user_id: str):
    db = get_supabase()
    result = db.table("user_profiles").select("resume_url").eq("user_id", user_id).single().execute()
    if not result.data or not result.data.get("resume_url"):
        raise HTTPException(status_code=404, detail="No resume found")
    return {"pdf_url": result.data["resume_url"]}
