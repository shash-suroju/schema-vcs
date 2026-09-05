from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates

from .config import settings
from .db import make_pool, ping

templates = Jinja2Templates(directory="app/templates")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.catalog = make_pool(settings.catalog_dsn)
    await app.state.catalog.open()
    yield
    await app.state.catalog.close()


app = FastAPI(title="Schema VCS", lifespan=lifespan)


@app.get("/healthz")
async def healthz(request: Request) -> JSONResponse:
    checks: dict[str, str] = {}
    ok = True

    try:
        checks["catalog"] = await ping(request.app.state.catalog)
    except Exception as exc:
        checks["catalog"] = f"unreachable: {exc.__class__.__name__}"
        ok = False

    # The target DB is user-supplied and may legitimately be unreachable.
    # That's a product state to surface, not a reason to fail the health check.
    if settings.demo_target_dsn:
        pool = make_pool(settings.demo_target_dsn)
        try:
            await pool.open(wait=True, timeout=5)
            checks["demo_target"] = await ping(pool)
        except Exception as exc:
            checks["demo_target"] = f"unreachable: {exc.__class__.__name__}"
        finally:
            await pool.close()

    return JSONResponse(
        {"status": "ok" if ok else "degraded", "env": settings.app_env, "checks": checks},
        status_code=200 if ok else 503,
    )


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html", {"env": settings.app_env})