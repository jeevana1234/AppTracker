from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from app.routers import jobs, universities, resume, auth, monitor
import asyncio
import logging

logger = logging.getLogger(__name__)


async def _hourly_job_monitor():
    """Background task: scan for new jobs every hour."""
    from app.services.job_monitor_service import run_job_monitor_for_all_users
    while True:
        try:
            await run_job_monitor_for_all_users()
        except Exception as e:
            logger.error(f"Hourly job monitor error: {e}")
        await asyncio.sleep(3600)  # 1 hour


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(_hourly_job_monitor())
    yield
    task.cancel()


app = FastAPI(
    title="AppTrack API",
    description="AI-powered job and university application tracker",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(jobs.router, prefix="/jobs", tags=["Jobs"])
app.include_router(universities.router, prefix="/universities", tags=["Universities"])
app.include_router(resume.router, prefix="/resume", tags=["Resume"])
app.include_router(monitor.router, tags=["Monitor"])

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Ensure all unhandled 500s return JSON with CORS headers (not plain text)."""
    return JSONResponse(
        status_code=500,
        content={"detail": f"Internal server error: {str(exc)}"},
    )


@app.get("/")
def root():
    return {"message": "AppTrack API is running"}

@app.get("/health")
def health():
    return {"status": "ok"}
