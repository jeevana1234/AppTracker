"""
Job Monitor Service
- Searches LinkedIn, Indeed, Naukri for jobs matching user preferences
- Stores new findings in job_alerts table
- Sends Firebase push notifications
"""
import asyncio
import json
import logging
from datetime import datetime
from playwright.async_api import async_playwright
from supabase import create_client
from app.config import SUPABASE_URL, SUPABASE_KEY, FIREBASE_SERVER_KEY
import httpx

logger = logging.getLogger(__name__)


async def search_jobs_for_user(user_id: str, preferences: dict) -> list[dict]:
    """Search LinkedIn/Indeed for jobs matching user preferences."""
    roles = preferences.get("roles", [])
    locations = preferences.get("locations", ["Remote"])
    results = []

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        )

        for role in roles[:3]:  # limit to first 3 roles per run
            for location in locations[:2]:
                try:
                    query = f"{role} {location}".replace(" ", "+")
                    # Use LinkedIn public job search
                    url = f"https://www.linkedin.com/jobs/search/?keywords={query}&f_TPR=r86400"
                    await page.goto(url, timeout=20000)
                    await page.wait_for_timeout(2000)

                    job_cards = await page.query_selector_all(
                        ".job-search-card, .base-card"
                    )
                    for card in job_cards[:10]:
                        try:
                            title = await card.query_selector(".base-search-card__title")
                            company = await card.query_selector(".base-search-card__subtitle")
                            loc = await card.query_selector(".job-search-card__location")
                            link = await card.query_selector("a")

                            title_text = (await title.inner_text()).strip() if title else ""
                            company_text = (await company.inner_text()).strip() if company else ""
                            loc_text = (await loc.inner_text()).strip() if loc else location
                            href = await link.get_attribute("href") if link else ""

                            if title_text and company_text:
                                results.append({
                                    "user_id": user_id,
                                    "title": title_text,
                                    "company": company_text,
                                    "location": loc_text,
                                    "job_url": href.split("?")[0] if href else "",
                                    "source": "LinkedIn",
                                    "matched_keywords": [role],
                                    "status": "new",
                                })
                        except Exception:
                            continue
                except Exception as e:
                    logger.warning(f"LinkedIn search failed for {role}: {e}")

                await asyncio.sleep(1)

        await browser.close()

    return results


async def save_new_alerts(user_id: str, jobs: list[dict]) -> list[dict]:
    """Save new job alerts, skipping duplicates by URL."""
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    new_jobs = []

    # Get existing URLs for this user
    existing = sb.table("job_alerts") \
        .select("job_url") \
        .eq("user_id", user_id) \
        .execute()
    existing_urls = {r["job_url"] for r in (existing.data or [])}

    for job in jobs:
        if job["job_url"] not in existing_urls:
            try:
                sb.table("job_alerts").insert(job).execute()
                new_jobs.append(job)
                existing_urls.add(job["job_url"])
            except Exception as e:
                logger.error(f"Failed to save job alert: {e}")

    return new_jobs


async def send_push_notification(fcm_token: str, title: str, body: str, data: dict = None):
    """Send Firebase Cloud Messaging push notification."""
    if not FIREBASE_SERVER_KEY or FIREBASE_SERVER_KEY == "your_firebase_server_key_here":
        logger.info(f"[NOTIFICATION SKIPPED - no Firebase key] {title}: {body}")
        return

    payload = {
        "to": fcm_token,
        "notification": {"title": title, "body": body, "sound": "default"},
        "data": data or {},
        "priority": "high",
    }
    async with httpx.AsyncClient() as client:
        try:
            await client.post(
                "https://fcm.googleapis.com/fcm/send",
                headers={
                    "Authorization": f"key={FIREBASE_SERVER_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=10,
            )
        except Exception as e:
            logger.error(f"FCM notification failed: {e}")


async def run_job_monitor_for_all_users():
    """Main scheduled task — runs every hour via APScheduler."""
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    try:
        prefs_list = sb.table("job_preferences") \
            .select("*, user_profiles(fcm_token)") \
            .eq("is_active", True) \
            .execute()

        for pref in (prefs_list.data or []):
            user_id = pref["user_id"]
            try:
                # Search for new jobs
                jobs = await search_jobs_for_user(user_id, pref)
                new_jobs = await save_new_alerts(user_id, jobs)

                if new_jobs:
                    count = len(new_jobs)
                    titles = ", ".join(j["title"] for j in new_jobs[:2])
                    msg = f"{titles}{'...' if count > 2 else ''}"

                    # Get user FCM token
                    profile = pref.get("user_profiles") or {}
                    fcm_token = profile.get("fcm_token") if isinstance(profile, dict) else None
                    if fcm_token:
                        await send_push_notification(
                            fcm_token,
                            f"🎯 {count} new job{'s' if count > 1 else ''} found!",
                            msg,
                            {"type": "job_alert", "count": str(count)},
                        )

                    logger.info(f"User {user_id}: found {count} new jobs")

                pref_id = pref.get("id")
                if pref_id:
                    sb.table("job_preferences") \
                        .update({"last_checked": datetime.utcnow().isoformat()}) \
                        .eq("id", pref_id) \
                        .execute()

            except Exception as e:
                logger.error(f"Job monitor failed for user {user_id}: {e}")

    except Exception as e:
        logger.error(f"Job monitor run failed: {e}")
