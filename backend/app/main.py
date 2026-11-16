from fastapi import APIRouter, FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from app.auth import router as auth_router
from app.profiles import router as profiles_router
from app.documents import router as documents_router
from app.administration import router as administration_router
from app.proposals import router as proposals_router
from app.notifications import router as notifications_router
from app.config import get_settings
from contextlib import asynccontextmanager
from app.db import get_engine

@asynccontextmanager
async def lifespan(app):
    get_settings()  # Fail startup for invalid production delivery/security settings.
    yield


app = FastAPI(title='Jain Matrimonial API', version='0.5.0', lifespan=lifespan,
              description='Private consultancy API. Customer OTP and separate administrator authentication.')
router = APIRouter(prefix='/api/v1', tags=['system'])


@router.get('/health')
def health():
    return {'status': 'ok', 'service': 'jain-matrimonial', 'phase': 5}


@router.get('/ready')
def ready():
    try:
        with get_engine().connect() as connection:
            revision = connection.execute(text('SELECT version_num FROM alembic_version')).scalar()
            roles = set(connection.execute(text('SELECT name FROM roles')).scalars())
            if revision != '0005' or roles != {'CUSTOMER', 'ADMINISTRATOR'}:
                raise HTTPException(503, 'Database migrations required')
    except SQLAlchemyError:
        raise HTTPException(503, 'Database unavailable or migrations required') from None
    return {'status': 'ready', 'database': 'postgresql', 'revision': revision}


app.include_router(router)
app.include_router(auth_router)
app.include_router(profiles_router)
app.include_router(documents_router)
app.include_router(administration_router)
app.include_router(proposals_router)
app.include_router(notifications_router)


@app.middleware('http')
async def security_headers(request, call_next):
    if get_settings().environment == 'production' and request.url.scheme != 'https':
        response = JSONResponse({'detail': 'HTTPS required'}, status_code=426)
    else:
        response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    if get_settings().environment == 'production':
        response.headers['Strict-Transport-Security'] = 'max-age=31536000'
    return response


@app.exception_handler(RequestValidationError)
async def invalid_request(request, exc):
    # Pydantic normally echoes rejected input, including passwords and codes.
    errors = [{'loc': error['loc'], 'type': error['type'], 'msg': 'Invalid value'} for error in exc.errors()]
    return JSONResponse({'detail': errors}, status_code=422)


@app.exception_handler(SQLAlchemyError)
async def unavailable_database(request, exc):
    return JSONResponse({'detail': 'Service temporarily unavailable'}, status_code=503)
