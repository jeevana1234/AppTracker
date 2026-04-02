from playwright.async_api import async_playwright
import httpx

async def scrape_career_page(url: str) -> list[dict]:
    """Scrape job listings from a given career page URL."""
    jobs = []
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        await page.goto(url, timeout=30000)
        await page.wait_for_load_state("networkidle")

        # Generic scraper - finds job titles and links on the page
        job_elements = await page.query_selector_all("a[href*='job'], a[href*='career'], a[href*='position']")
        for el in job_elements[:20]:  # limit to 20
            title = await el.inner_text()
            href = await el.get_attribute("href")
            if title.strip() and href:
                jobs.append({"title": title.strip(), "url": href})

        await browser.close()
    return jobs

async def search_jobs_duckduckgo(query: str) -> list[dict]:
    """Search for job postings using DuckDuckGo HTML search."""
    results = []
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://html.duckduckgo.com/html/",
            params={"q": query},
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15
        )
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(resp.text, "html.parser")
        for result in soup.select(".result__title")[:10]:
            link = result.find("a")
            if link:
                results.append({
                    "title": link.get_text(strip=True),
                    "url": link.get("href", "")
                })
    return results
