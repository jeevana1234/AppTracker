from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from app.services.resume_service import generate_resume_pdf, parse_uploaded_resume
from app.database import get_supabase

router = APIRouter()

class ResumeRequest(BaseModel):
    user_id: str
    job_description: str = ""
    template: str = "modern"   # classic | modern | minimalist | executive

@router.post("/generate")
async def generate_resume(request: ResumeRequest):
    try:
        db = get_supabase()
        profile = db.table("user_profiles").select("*").eq("user_id", request.user_id).maybe_single().execute()
        if not profile or not profile.data:
            raise HTTPException(status_code=404, detail="User profile not found. Please complete your Profile first.")
        pdf_url = await generate_resume_pdf(profile.data, request.job_description, request.template)
        return {"resume_url": pdf_url, "message": "Resume generated successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Resume generation failed: {str(e)}")

@router.post("/generate-from-upload")
async def generate_from_upload(
    file: UploadFile = File(...),
    template: str = Form("modern"),
    user_id: str = Form(...)):
    """Parse uploaded PDF and generate a new resume in the selected template."""
    try:
        content = await file.read()
        profile = await parse_uploaded_resume(content)
        profile['user_id'] = user_id
        # Fill contact fields from Supabase profile if missing
        db = get_supabase()
        db_row = db.table("user_profiles").select("*").eq("user_id", user_id).maybe_single().execute()
        if db_row and db_row.data:
            for key in ['email', 'phone', 'linkedin_url', 'github_url', 'portfolio_url']:
                if not profile.get(key) and db_row.data.get(key):
                    profile[key] = db_row.data[key]
        pdf_url = await generate_resume_pdf(profile, "", template)
        return {"resume_url": pdf_url, "message": "Resume generated from upload"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload generation failed: {str(e)}")

@router.post("/parse-upload")
async def parse_resume_upload(file: UploadFile = File(...)):
    """Parse an uploaded PDF and return extracted profile fields (preview only)."""
    content = await file.read()
    parsed = await parse_uploaded_resume(content)
    return parsed

@router.get("/download/{user_id}")
def get_resume_url(user_id: str):
    db = get_supabase()
    result = db.table("user_profiles").select("resume_url").eq("user_id", user_id).single().execute()
    if not result.data or not result.data.get("resume_url"):
        raise HTTPException(status_code=404, detail="No resume found")
    return {"resume_url": result.data["resume_url"]}
