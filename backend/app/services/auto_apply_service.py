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


# ──────────────────────────────────────────────────────────────────────────────
# Direct apply with portal login (for manually-added jobs)
# ──────────────────────────────────────────────────────────────────────────────

async def auto_apply_with_portal_login(profile: dict, job: dict) -> dict:
    """
    Auto-apply to a manually-added job.
    1. Navigate to job_url
    2. If portal_username + portal_password provided, log in first
    3. Fill all visible form fields with profile data (name, email, phone, etc.)
    4. Click Submit / Apply
    """
    job_url = job.get("job_url", "")
    if not job_url:
        return {"success": False, "message": "No job URL provided"}

    portal_username = job.get("portal_username", "")
    portal_password = job.get("portal_password", "")

    full_name = profile.get("full_name", "")
    name_parts = full_name.split(" ", 1)
    first_name = name_parts[0] if name_parts else ""
    last_name = name_parts[1] if len(name_parts) > 1 else ""
    email = profile.get("email", "")
    phone = profile.get("phone", "")
    linkedin = profile.get("linkedin_url", "")
    skills = profile.get("skills", "")
    summary = profile.get("summary", "")

    result: dict = {"success": False, "message": "Could not complete auto-apply"}

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            )
        )
        page = await context.new_page()

        try:
            await page.goto(job_url, timeout=30000)
            await page.wait_for_timeout(2000)

            # ── Step 1: Portal Login ──────────────────────────────────────
            if portal_username and portal_password:
                uname_selectors = [
                    "input[type='email']",
                    "input[name*='email' i]", "input[id*='email' i]",
                    "input[name*='username' i]", "input[id*='username' i]",
                    "input[name*='user' i]", "input[placeholder*='email' i]",
                    "input[placeholder*='username' i]",
                ]
                for sel in uname_selectors:
                    field = await page.query_selector(sel)
                    if field:
                        await field.fill(portal_username)
                        break

                pw_field = await page.query_selector("input[type='password']")
                if pw_field:
                    await pw_field.fill(portal_password)

                for sel in [
                    "button[type='submit']", "input[type='submit']",
                    "button:has-text('Sign in')", "button:has-text('Log in')",
                    "button:has-text('Login')", "button:has-text('Continue')",
                ]:
                    btn = await page.query_selector(sel)
                    if btn:
                        await btn.click()
                        await page.wait_for_timeout(3000)
                        break

            # ── Step 2: LinkedIn Easy Apply shortcut ──────────────────────
            easy_apply = await page.query_selector(
                "button:has-text('Easy Apply'), .jobs-apply-button"
            )
            if easy_apply:
                return await _handle_linkedin_easy_apply(page, profile)

            # ── Step 3: Generic form filling ──────────────────────────────
            filled = 0

            async def try_fill(selectors: list[str], value: str) -> None:
                nonlocal filled
                if not value:
                    return
                for sel in selectors:
                    field = await page.query_selector(sel)
                    if field:
                        try:
                            await field.fill(value)
                            filled += 1
                        except Exception:
                            pass
                        return

            await try_fill([
                "input[name*='full_name' i]", "input[id*='full_name' i]",
                "input[name*='fullname' i]", "input[placeholder*='full name' i]",
            ], full_name)

            await try_fill([
                "input[name*='first_name' i]", "input[id*='first_name' i]",
                "input[name*='firstname' i]", "input[placeholder*='first name' i]",
                "input[placeholder*='given name' i]",
            ], first_name)

            await try_fill([
                "input[name*='last_name' i]", "input[id*='last_name' i]",
                "input[name*='lastname' i]", "input[placeholder*='last name' i]",
                "input[placeholder*='surname' i]",
            ], last_name)

            await try_fill([
                "input[type='email']",
                "input[name*='email' i]", "input[id*='email' i]",
                "input[placeholder*='email' i]",
            ], email)

            await try_fill([
                "input[type='tel']",
                "input[name*='phone' i]", "input[id*='phone' i]",
                "input[placeholder*='phone' i]", "input[placeholder*='mobile' i]",
            ], phone)

            await try_fill([
                "input[name*='linkedin' i]", "input[id*='linkedin' i]",
                "input[placeholder*='linkedin' i]",
            ], linkedin)

            # Cover letter / summary
            for sel in [
                "textarea[name*='cover' i]", "textarea[id*='cover' i]",
                "textarea[name*='letter' i]", "textarea[placeholder*='cover' i]",
                "textarea[name*='summary' i]",
            ]:
                field = await page.query_selector(sel)
                if field and summary:
                    await field.fill(summary)
                    filled += 1
                    break

            # Skills
            for sel in [
                "textarea[name*='skills' i]", "input[name*='skills' i]",
                "textarea[placeholder*='skills' i]",
            ]:
                field = await page.query_selector(sel)
                if field and skills:
                    await field.fill(skills)
                    filled += 1
                    break

            # ── Step 4: Submit ────────────────────────────────────────────
            submit_selectors = [
                "button:has-text('Submit Application')",
                "button:has-text('Submit application')",
                "button:has-text('Submit')",
                "button:has-text('Apply Now')",
                "button:has-text('Apply now')",
                "button:has-text('Apply')",
                "input[type='submit'][value*='apply' i]",
                "input[type='submit']",
            ]
            submitted = False
            for sel in submit_selectors:
                btn = await page.query_selector(sel)
                if btn:
                    await btn.click()
                    await page.wait_for_timeout(2000)
                    submitted = True
                    break

            if submitted:
                result = {
                    "success": True,
                    "message": (
                        f"Applied to {job.get('role', 'role')} at "
                        f"{job.get('company', 'company')} "
                        f"({filled} field(s) filled)"
                    ),
                }
            elif filled > 0:
                result = {
                    "success": False,
                    "message": f"Filled {filled} field(s) but could not find submit button. May require manual submission.",
                }
            else:
                result = {
                    "success": False,
                    "message": "Could not find application form on this page. The site may require JavaScript interaction.",
                }

        except Exception as e:
            logger.error(f"Direct apply error for {job_url}: {e}")
            result = {"success": False, "message": str(e)}
        finally:
            await browser.close()

    return result


async def _handle_linkedin_easy_apply(page, profile: dict) -> dict:
    """Handle LinkedIn Easy Apply multi-step form."""
    try:
        easy_apply_btn = await page.query_selector(
            "button:has-text('Easy Apply'), .jobs-apply-button"
        )
        if easy_apply_btn:
            await easy_apply_btn.click()
            await page.wait_for_timeout(1500)

        phone_field = await page.query_selector(
            "input[id*='phone'], input[placeholder*='phone' i]"
        )
        if phone_field and profile.get("phone"):
            await phone_field.fill(profile["phone"])

        for _ in range(8):
            submit_btn = await page.query_selector(
                "button:has-text('Submit application'), "
                "button:has-text('Submit')"
            )
            next_btn = await page.query_selector("button:has-text('Next')")
            if submit_btn:
                await submit_btn.click()
                await page.wait_for_timeout(2000)
                return {"success": True, "message": "Applied via LinkedIn Easy Apply"}
            elif next_btn:
                await next_btn.click()
                await page.wait_for_timeout(1000)
            else:
                break
    except Exception as e:
        return {"success": False, "message": str(e)}

    return {"success": False, "message": "Could not complete LinkedIn Easy Apply"}
