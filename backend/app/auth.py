import hmac
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator
from sqlalchemy import insert, select, update, text
from app.config import get_settings
from app.db import get_engine
from app import models as m
from app.mailer import send_otp
from app.security import keyed_hash, token_hash, hash_password, verify_password

router = APIRouter(prefix='/api/v1', tags=['authentication'])
bearer = HTTPBearer(auto_error=False)
# Unknown accounts still incur the same password derivation work.
DUMMY_PASSWORD_HASH = hash_password('unused-' + secrets.token_urlsafe(24))


class EmailInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    email: str = Field(min_length=3, max_length=254)

    @field_validator('email')
    @classmethod
    def normalize_email(cls, value):
        value = value.strip().lower()
        pattern = r"[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+"
        if not re.fullmatch(pattern, value) or len(value.split('@')[0]) > 64:
            raise ValueError('Enter a valid email address')
        local, domain = value.split('@')
        if local.startswith('.') or local.endswith('.') or '..' in local or any(len(p) > 63 for p in domain.split('.')):
            raise ValueError('Enter a valid email address')
        return value


class VerifyInput(EmailInput):
    code: str = Field(pattern=r'^[0-9]{6}$')


class AdminInput(EmailInput):
    password: SecretStr = Field(min_length=1, max_length=128)


class RefreshInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    refresh_token: SecretStr = Field(min_length=40, max_length=200)


def now():
    return datetime.now(timezone.utc)


def secret():
    value = get_settings().auth_secret.get_secret_value()
    if len(value) < 32:
        raise HTTPException(503, 'Authentication is not configured')
    return value


def lock(connection, key):
    connection.execute(text('SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))'), {'key': key})


def rate_limit(scope: str, identity: str, maximum: int, seconds: int):
    key = keyed_hash(secret(), f'rate:{scope}:{identity}')
    denied = False
    with get_engine().begin() as connection:
        lock(connection, key)
        row = connection.execute(select(m.rate_limits).where(m.rate_limits.c.key_hash == key)).mappings().first()
        current = now()
        if row is None:
            connection.execute(insert(m.rate_limits).values(key_hash=key, window_start=current, request_count=1))
        elif current >= row['window_start'] + timedelta(seconds=seconds):
            connection.execute(update(m.rate_limits).where(m.rate_limits.c.id == row['id']).values(window_start=current, request_count=1))
        elif row['request_count'] >= maximum:
            denied = True
        else:
            connection.execute(update(m.rate_limits).where(m.rate_limits.c.id == row['id']).values(request_count=row['request_count'] + 1))
    if denied:
        raise HTTPException(429, 'Too many attempts. Please try again later.', headers={'Retry-After': str(seconds)})


def limit_request(request, email, scope, per_email, per_ip):
    ip = request.client.host if request.client else 'unknown'
    rate_limit(scope + ':ip', ip, per_ip, 3600)
    rate_limit(scope + ':email', email, per_email, 3600)


def record(connection, action, actor_id=None, entity_id=None):
    connection.execute(insert(m.audit).values(actor_id=actor_id, action=action, entity_type='authentication', entity_id=entity_id))


def user_query():
    return select(m.users.c.id, m.users.c.email, m.users.c.active, m.users.c.password_hash,
                  m.roles.c.name.label('role')).select_from(
        m.users.join(m.user_roles, m.users.c.id == m.user_roles.c.user_id)
        .join(m.roles, m.roles.c.id == m.user_roles.c.role_id))


def issue_session(connection, user_id, session=None):
    access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    current = now()
    refresh_expiry = session['refresh_expires_at'].astimezone(timezone.utc) if session else current + timedelta(days=7)
    access_expiry = min(current + timedelta(minutes=15), refresh_expiry)
    values = dict(access_hash=token_hash(access), refresh_hash=token_hash(refresh),
                  access_expires_at=access_expiry, refresh_expires_at=refresh_expiry)
    if session:
        connection.execute(update(m.sessions).where(m.sessions.c.id == session['id']).values(**values))
    else:
        connection.execute(insert(m.sessions).values(user_id=user_id, **values))
    return dict(access_token=access, refresh_token=refresh, token_type='bearer',
                expires_in=max(0, int((access_expiry-current).total_seconds())), refresh_expires_at=refresh_expiry)


@router.post('/auth/otp/request', status_code=202)
def request_otp(body: EmailInput, request: Request):
    settings = get_settings()
    limit_request(request, body.email, 'otp-request', 5, 20)
    failure = None
    code = f'{secrets.randbelow(1_000_000):06d}'
    with get_engine().begin() as connection:
        lock(connection, keyed_hash(secret(), 'otp:' + body.email))
        current = now()
        recent = connection.execute(select(m.otp).where(m.otp.c.email == body.email)
                                    .order_by(m.otp.c.created_at.desc()).limit(1)).mappings().first()
        if recent and current < recent['resend_after']:
            failure = (429, 'Please wait 60 seconds before requesting another code')
        else:
            connection.execute(update(m.otp).where(m.otp.c.email == body.email, m.otp.c.consumed_at.is_(None)).values(consumed_at=current))
            otp_id = connection.execute(insert(m.otp).values(email=body.email,
                code_hash=keyed_hash(secret(), f'otp:{body.email}:{code}'),
                expires_at=current+timedelta(minutes=5), resend_after=current+timedelta(seconds=60))
                .returning(m.otp.c.id)).scalar_one()
            if settings.otp_delivery == 'smtp':
                try:
                    send_otp(settings, body.email, code)
                except Exception:
                    # Do not log exception content: SMTP responses may contain addresses or codes.
                    connection.execute(update(m.otp).where(m.otp.c.id == otp_id).values(consumed_at=current))
                    failure = (503, 'Email delivery is unavailable. Please try again later.')
            record(connection, 'OTP_REQUESTED' if not failure else 'OTP_DELIVERY_FAILED', entity_id=otp_id)
    if failure:
        raise HTTPException(*failure, headers={'Retry-After': '60'} if failure[0] == 429 else None)
    result = {'message': 'A sign-in code has been requested.', 'expires_in': 300, 'resend_after': 60}
    if settings.environment != 'production' and settings.otp_delivery == 'development':
        result['development_otp'] = code
    return result


@router.post('/auth/otp/verify')
def verify_otp(body: VerifyInput, request: Request):
    limit_request(request, body.email, 'otp-verify', 30, 60)
    result = None
    with get_engine().begin() as connection:
        lock(connection, keyed_hash(secret(), 'otp:' + body.email))
        current = now()
        otp = connection.execute(select(m.otp).where(m.otp.c.email == body.email)
                                 .order_by(m.otp.c.created_at.desc()).limit(1).with_for_update()).mappings().first()
        eligible = otp and otp['consumed_at'] is None and otp['expires_at'] > current and otp['attempts'] < 5
        if eligible:
            matches = hmac.compare_digest(otp['code_hash'], keyed_hash(secret(), f'otp:{body.email}:{body.code}'))
            if not matches:
                connection.execute(update(m.otp).where(m.otp.c.id == otp['id']).values(attempts=otp['attempts']+1))
                record(connection, 'OTP_FAILED', entity_id=otp['id'])
            else:
                connection.execute(update(m.otp).where(m.otp.c.id == otp['id']).values(consumed_at=current))
                user = connection.execute(user_query().where(m.users.c.email == body.email)).mappings().first()
                exists = connection.execute(select(m.users.c.id).where(m.users.c.email == body.email)).scalar_one_or_none()
                if exists is None:
                    user_id = connection.execute(insert(m.users).values(email=body.email, email_verified_at=current).returning(m.users.c.id)).scalar_one()
                    role_id = connection.execute(select(m.roles.c.id).where(m.roles.c.name == 'CUSTOMER')).scalar_one()
                    connection.execute(insert(m.user_roles).values(user_id=user_id, role_id=role_id))
                    connection.execute(insert(m.notifications).values(user_id=user_id, event='REGISTRATION_COMPLETED', message='Your account is ready. Welcome to Jain Matrimonial.'))
                    record(connection, 'CUSTOMER_REGISTERED', user_id, user_id)
                    user = connection.execute(user_query().where(m.users.c.id == user_id)).mappings().one()
                if user and user['active'] and user['role'] == 'CUSTOMER':
                    connection.execute(update(m.users).where(m.users.c.id == user['id'], m.users.c.email_verified_at.is_(None))
                        .values(email_verified_at=current, version=m.users.c.version+1))
                    result = issue_session(connection, user['id'])
                    record(connection, 'CUSTOMER_LOGIN', user['id'], user['id'])
    if result is None:
        raise HTTPException(401, 'Invalid, expired or unavailable sign-in code')
    return result


@router.post('/auth/admin/login')
def admin_login(body: AdminInput, request: Request):
    limit_request(request, body.email, 'admin-login', 5, 30)
    result = None
    with get_engine().begin() as connection:
        # Serialise login with account deactivation or password changes.
        user = connection.execute(user_query().where(m.users.c.email == body.email).with_for_update(of=m.users)).mappings().first()
        valid = verify_password(body.password.get_secret_value(), user['password_hash'] if user and user['password_hash'] else DUMMY_PASSWORD_HASH)
        if user and valid and user['active'] and user['role'] == 'ADMINISTRATOR':
            result = issue_session(connection, user['id'])
            record(connection, 'ADMINISTRATOR_LOGIN', user['id'], user['id'])
        else:
            record(connection, 'ADMINISTRATOR_LOGIN_FAILED')
    if result is None:
        raise HTTPException(401, 'Invalid login credentials')
    return result


@router.post('/auth/refresh')
def refresh_session(body: RefreshInput, request: Request):
    rate_limit('refresh:ip', request.client.host if request.client else 'unknown', 120, 3600)
    result = None
    with get_engine().begin() as connection:
        session = connection.execute(select(m.sessions).where(m.sessions.c.refresh_hash == token_hash(body.refresh_token.get_secret_value())).with_for_update()).mappings().first()
        if session and session['revoked_at'] is None and session['refresh_expires_at'] > now():
            user = connection.execute(user_query().where(m.users.c.id == session['user_id'])).mappings().first()
            if user and user['active']:
                result = issue_session(connection, user['id'], session)
                record(connection, 'SESSION_REFRESHED', user['id'], session['id'])
    if result is None:
        raise HTTPException(401, 'Session expired or invalid')
    return result


@router.post('/auth/logout', status_code=204)
def logout(body: RefreshInput):
    # Refresh-token possession permits logout even after the access token expires.
    with get_engine().begin() as connection:
        session = connection.execute(select(m.sessions).where(m.sessions.c.refresh_hash == token_hash(body.refresh_token.get_secret_value())).with_for_update()).mappings().first()
        if session and session['revoked_at'] is None:
            connection.execute(update(m.sessions).where(m.sessions.c.id == session['id']).values(revoked_at=now()))
            record(connection, 'SESSION_LOGOUT', session['user_id'], session['id'])
    return Response(status_code=204)


def current_user(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
    if credentials is not None:
        with get_engine().connect() as connection:
            user = connection.execute(user_query().join(m.sessions, m.sessions.c.user_id == m.users.c.id)
                .where(m.sessions.c.access_hash == token_hash(credentials.credentials),
                       m.sessions.c.revoked_at.is_(None), m.sessions.c.access_expires_at > now(), m.users.c.active.is_(True))).mappings().first()
            if user:
                return {'id': str(user['id']), 'email': user['email'], 'role': user['role']}
    raise HTTPException(401, 'Authentication required', headers={'WWW-Authenticate': 'Bearer'})


def require_role(role):
    def dependency(user: Annotated[dict, Depends(current_user)]):
        if user['role'] != role:
            raise HTTPException(403, 'Access denied')
        return user
    return dependency


@router.get('/auth/me')
def me(user: Annotated[dict, Depends(current_user)]):
    return user


@router.get('/admin/session')
def admin_session(user: Annotated[dict, Depends(require_role('ADMINISTRATOR'))]):
    return user


@router.get('/customer/session')
def customer_session(user: Annotated[dict, Depends(require_role('CUSTOMER'))]):
    return user
