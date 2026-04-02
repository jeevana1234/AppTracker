from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from supabase import create_client
from app.config import SUPABASE_URL, SUPABASE_KEY
from app.services.job_monitor_service import run_job_monitor_for_all_users, search_jobs_for_user, save_new_alerts
from app.services.auto_apply_service import auto_apply_to_job
from typing import Optional

router = APIRouter(prefix="/monitor", tags=["monitor"])


class JobPreferences(BaseModel):
    user_id: str
    roles: list[str]
    keywords: list[str] = []
    locations: list[str] = ["Remote"]
    experience_level: str = "mid"
    auto_apply: bool = False
    is_active: bool = True


class AutoApplyRequest(BaseModel):
    user_id: str
    job_alert_id: str


class UniMonitorRequest(BaseModel):
    user_id: str
    uni_application_id: str
    portal_url: str
    portal_username: Optional[str] = None
    portal_password: Optional[str] = None


# ─── Job Preferences ───────────────────────────────────────────────────────────

@router.post("/preferences")
async def save_preferences(prefs: JobPreferences):
    """Save job search preferences for a user."""
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    existing = sb.table("job_preferences").select("id").eq("user_id", prefs.user_id).execute()
    if existing.data:
        result = sb.table("job_preferences") \
            .update(prefs.model_dump()) \
            .eq("user_id", prefs.user_id) \
            .execute()
    else:
        result = sb.table("job_preferences").insert(prefs.model_dump()).execute()
    return {"status": "saved", "data": result.data}


@router.get("/preferences/{user_id}")
async def get_preferences(user_id: str):
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    result = sb.table("job_preferences").select("*").eq("user_id", user_id).execute()
    return result.data[0] if result.data else {}


# ─── Job Alerts ────────────────────────────────────────────────────────────────

@router.get("/alerts/{user_id}")
async def get_alerts(user_id: str):
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    result = sb.table("job_alerts") \
        .select("*") \
        .eq("user_id", user_id) \
        .order("created_at", desc=True) \
        .limit(50) \
        .execute()
    return result.data or []


@router.post("/scan/{user_id}")
async def trigger_scan(user_id: str):
    """Manually trigger a job scan for a specific user."""
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    prefs_result = sb.table("job_preferences").select("*").eq("user_id", user_id).execute()
    if not prefs_result.data:
        raise HTTPException(status_code=404, detail="No job preferences found. Set up preferences first.")

    prefs = prefs_result.data[0]
    jobs = await search_jobs_for_user(user_id, prefs)
    new_jobs = await save_new_alerts(user_id, jobs)
    return {"found": len(jobs), "new": len(new_jobs), "jobs": new_jobs}


@router.patch("/alerts/{alert_id}/dismiss")
async def dismiss_alert(alert_id: str):
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    sb.table("job_alerts").update({"status": "dismissed"}).eq("id", alert_id).execute()
    return {"status": "dismissed"}


# ─── Auto Apply ────────────────────────────────────────────────────────────────

@router.post("/auto-apply")
async def auto_apply(req: AutoApplyRequest):
    """Auto-apply to a specific job alert using Playwright."""
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)

    profile_res = sb.table("user_profiles").select("*").eq("user_id", req.user_id).execute()
    if not profile_res.data:
        raise HTTPException(status_code=404, detail="Profile not found")

    job_res = sb.table("job_alerts").select("*").eq("id", req.job_alert_id).execute()
    if not job_res.data:
        raise HTTPException(status_code=404, detail="Job alert not found")

    profile = profile_res.data[0]
    job = job_res.data[0]

    result = await auto_apply_to_job(profile, job)
    return result


# ─── University Portal Monitor ─────────────────────────────────────────────────

@router.post("/uni-check")
async def check_uni_portal(req: UniMonitorRequest):
    """
    Check a university portal for status updates using Playwright.
    Returns current page text / status snippet.
    """
    from playwright.async_api import async_playwright

    result_text = ""
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        try:
            await page.goto(req.portal_url, timeout=20000)
            await page.wait_for_timeout(2000)

            # Auto-login if credentials provided
            if req.portal_username and req.portal_password:
                for sel in ["input[type='email']", "input[name*='user']", "input[id*='user']"]:
                    field = await page.query_selector(sel)
                    if field:
                        await field.fill(req.portal_username)
                        break
                for sel in ["input[type='password']"]:
                    field = await page.query_selector(sel)
                    if field:
                        await field.fill(req.portal_password)
                        break
                for sel in ["button[type='submit']", "input[type='submit']", "button:has-text('Login')"]:
                    btn = await page.query_selector(sel)
                    if btn:
                        await btn.click()
                        await page.wait_for_timeout(2000)
                        break

            # Extract visible text (first 1000 chars)
            body = await page.query_selector("body")
            result_text = (await body.inner_text())[:1000] if body else ""

            # Update last_checked in DB
            sb = create_client(SUPABASE_URL, SUPABASE_KEY)
            from datetime import datetime
            sb.table("uni_applications") \
                .update({"last_checked": datetime.utcnow().isoformat()}) \
                .eq("id", req.uni_application_id) \
                .execute()

        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
        finally:
            await browser.close()

    return {"portal_text": result_text, "checked_at": __import__('datetime').datetime.utcnow().isoformat()}


# ─── Admin: run full scan ───────────────────────────────────────────────────────

@router.post("/run-full-scan")
async def run_full_scan():
    """Admin endpoint: trigger job monitor for all active users."""
    await run_job_monitor_for_all_users()
    return {"status": "completed"}
