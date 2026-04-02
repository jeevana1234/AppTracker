"""
Auto-Apply Service
Playwright automatically fills and submits job applications.
Sends push notification after each submission.
"""
import logging
from playwright.async_api import async_playwright
from supabase import create_client
from app.config import SUPABASE_URL, SUPABASE_KEY
from app.services.job_monitor_service import send_push_notification

logger = logging.getLogger(__name__)


async def auto_apply_to_job(profile: dict, job: dict) -> dict:
    """
    Attempt to auto-apply to a job using LinkedIn Easy Apply or direct form.
    Returns dict with success status and message.
    """
    job_url = job.get("job_url", "")
    if not job_url:
        return {"success": False, "message": "No job URL"}

    result = {"success": False, "message": "Auto-apply not supported for this job"}

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        )
        page = await context.new_page()

        try:
            await page.goto(job_url, timeout=20000)
            await page.wait_for_timeout(2000)

            # --- LinkedIn Easy Apply ---
            easy_apply_btn = await page.query_selector(
                "button:has-text('Easy Apply'), .jobs-apply-button"
            )
            if easy_apply_btn:
                await easy_apply_btn.click()
                await page.wait_for_timeout(1500)

                # Fill phone if prompted
                phone_field = await page.query_selector(
                    "input[id*='phone'], input[placeholder*='phone']"
                )
                if phone_field and profile.get("phone"):
                    await phone_field.fill(profile["phone"])

                # Submit / Next buttons
                for _ in range(5):
                    submit_btn = await page.query_selector(
                        "button:has-text('Submit application'), "
                        "button:has-text('Submit'), "
                        "button:has-text('Apply')"
                    )
                    next_btn = await page.query_selector("button:has-text('Next')")

                    if submit_btn:
                        await submit_btn.click()
                        await page.wait_for_timeout(2000)
                        result = {
                            "success": True,
                            "message": f"Applied to {job.get('title')} at {job.get('company')} via LinkedIn Easy Apply",
                        }
                        break
                    elif next_btn:
                        await next_btn.click()
                        await page.wait_for_timeout(1000)
                    else:
                        break

        except Exception as e:
            logger.error(f"Auto-apply error for {job_url}: {e}")
            result = {"success": False, "message": str(e)}
        finally:
            await browser.close()

    # Save result to DB
    if result["success"]:
        sb = create_client(SUPABASE_URL, SUPABASE_KEY)
        from datetime import datetime
        sb.table("job_alerts") \
            .update({"status": "applied", "applied_at": datetime.utcnow().isoformat()}) \
            .eq("id", job.get("id")) \
            .execute()

        # Also add to job_applications table
        sb.table("job_applications").insert({
            "user_id": profile["user_id"],
            "company": job.get("company", ""),
            "role": job.get("title", ""),
            "status": "applied",
            "job_url": job_url,
            "notes": "Auto-applied via AppTrack",
        }).execute()

        # Send push notification
        fcm_token = profile.get("fcm_token")
        if fcm_token:
            await send_push_notification(
                fcm_token,
                "✅ Application Submitted!",
                f"Applied to {job.get('title')} at {job.get('company')}",
                {"type": "auto_applied", "job_id": str(job.get("id", ""))},
            )

    return result
