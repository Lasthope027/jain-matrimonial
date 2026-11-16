from typing import Annotated
from uuid import UUID
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, insert, update, delete, exists, cast, String, or_, func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app import models as m
from app.auth import current_user, require_role, now, rate_limit
from app.db import get_engine
from app.profile_schemas import ProfileData, AdminCreate, EditProfile, Association, Verification
from app.workflow import lock_workflow,cancel_affected

router = APIRouter(prefix='/api/v1', tags=['profiles'])
User = Annotated[dict, Depends(current_user)]
Admin = Annotated[dict, Depends(require_role('ADMINISTRATOR'))]
Customer = Annotated[dict, Depends(require_role('CUSTOMER'))]
SECTIONS = {'education': m.education, 'family': m.family, 'preferences': m.preferences}


def audit(connection, user, action, profile_id, details=None):
    connection.execute(insert(m.audit).values(actor_id=UUID(user['id']), action=action,
        entity_type='profile', entity_id=profile_id, details=details))


def access(connection, profile_id, user, *, locked=False):
    query = select(m.profiles).where(m.profiles.c.id == profile_id)
    if user['role'] != 'ADMINISTRATOR':
        query = query.where(exists(select(m.account_profiles.c.id).where(
            m.account_profiles.c.profile_id == profile_id, m.account_profiles.c.account_id == UUID(user['id']))))
    if locked:
        query = query.with_for_update()
    profile = connection.execute(query).mappings().first()
    if not profile:
        # Unrelated customers cannot distinguish private IDs from missing records.
        raise HTTPException(404, 'Profile not found')
    return profile


def expected(profile, version):
    if profile['version'] != version:
        raise HTTPException(409, 'This profile has changed. Reload it before saving.')


def editable(profile, user):
    if profile['status'] == 'INACTIVE' and user['role'] != 'ADMINISTRATOR':
        raise HTTPException(409, 'This profile is inactive. Contact the consultancy.')


def notify(connection, profile_id, event, message):
    owner = connection.execute(select(m.account_profiles.c.account_id).where(m.account_profiles.c.profile_id == profile_id)).scalar_one_or_none()
    if owner:
        connection.execute(insert(m.notifications).values(user_id=owner, event=event, message=message,profile_id=profile_id))


def changed(connection, profile, user, action):
    cancel_affected(connection,user['id'],'Profile details or documents changed',profile_id=profile['id'])
    status = 'PENDING_VERIFICATION' if profile['status'] in ('APPROVED', 'REJECTED') else profile['status']
    values = dict(version=profile['version'] + 1, status=status)
    if status == 'PENDING_VERIFICATION':
        values.update(verified_by=None, verification_note=None)
    connection.execute(update(m.profiles).where(m.profiles.c.id == profile['id']).values(**values))
    audit(connection, user, action, profile['id'])
    if status == 'PENDING_VERIFICATION':
        notify(connection, profile['id'], 'PROFILE_SUBMITTED', 'Your updated profile is pending verification.')


def customer_id(connection, email):
    query = select(m.users.c.id).select_from(m.users.join(m.user_roles, m.users.c.id == m.user_roles.c.user_id)
        .join(m.roles, m.roles.c.id == m.user_roles.c.role_id)).where(
            m.users.c.email == email, m.users.c.active.is_(True), m.roles.c.name == 'CUSTOMER')
    result = connection.execute(query).scalar_one_or_none()
    if not result:
        raise HTTPException(422, 'An active registered customer with that email is required')
    return result


def details(connection, profile, user):
    data = dict(profile)
    for name, table in SECTIONS.items():
        section = connection.execute(select(table).where(table.c.profile_id == profile['id'])).mappings().first()
        data[name] = {k: v for k, v in (section or {}).items() if k not in ('id', 'profile_id', 'created_at', 'updated_at')}
    if user['role'] == 'ADMINISTRATOR':
        data['account_email'] = connection.execute(select(m.users.c.email).join(m.account_profiles,
            m.account_profiles.c.account_id == m.users.c.id).where(m.account_profiles.c.profile_id == profile['id'])).scalar_one_or_none()
    return data


def create(connection, body, user, *, administrator=False):
    lock_workflow(connection)
    data = body.model_dump(exclude={'education', 'family', 'preferences', 'account_email', 'status'})
    owner = customer_id(connection, body.account_email) if administrator and body.account_email else (None if administrator else UUID(user['id']))
    status = body.status if administrator else 'PENDING_VERIFICATION'
    profile_id = connection.execute(insert(m.profiles).values(**data, created_by=UUID(user['id']),
        status=status, verified_by=UUID(user['id']) if status == 'APPROVED' else None).returning(m.profiles.c.id)).scalar_one()
    for name, table in SECTIONS.items():
        connection.execute(insert(table).values(profile_id=profile_id, **getattr(body, name).model_dump()))
    if owner:
        connection.execute(insert(m.account_profiles).values(account_id=owner, profile_id=profile_id))
    audit(connection, user, 'PROFILE_CREATED', profile_id)
    notify(connection, profile_id, 'PROFILE_APPROVED' if status == 'APPROVED' else 'PROFILE_SUBMITTED',
           'Your profile is approved.' if status == 'APPROVED' else 'Your profile is pending verification.')
    return details(connection, access(connection, profile_id, user), user)


def listing(connection, user, offset, limit, *, q=None, gender=None, age_min=None, age_max=None,
            location=None, community=None, status=None, unassociated_only=False):
    query = select(m.profiles.c.id, m.profiles.c.full_name, m.profiles.c.gender,
        m.profiles.c.date_of_birth, m.profiles.c.current_location, m.profiles.c.community,
        m.profiles.c.status, m.profiles.c.version, m.profiles.c.updated_at)
    if user['role'] != 'ADMINISTRATOR':
        query = query.where(exists(select(m.account_profiles.c.id).where(
            m.account_profiles.c.profile_id == m.profiles.c.id,
            m.account_profiles.c.account_id == UUID(user['id']))))
    if q:
        query = query.where(or_(m.profiles.c.full_name.icontains(q, autoescape=True),
                               cast(m.profiles.c.id, String).icontains(q, autoescape=True)))
    if gender:
        query = query.where(m.profiles.c.gender == gender)
    age = func.extract('year', func.age(func.current_date(), m.profiles.c.date_of_birth))
    if age_min is not None:
        query = query.where(age >= age_min)
    if age_max is not None:
        query = query.where(age <= age_max)
    if location:
        query = query.where(m.profiles.c.current_location.icontains(location, autoescape=True))
    if community:
        query = query.where(m.profiles.c.community.icontains(community, autoescape=True))
    if status:
        query = query.where(m.profiles.c.status == status)
    if unassociated_only:
        query = query.where(~exists(select(m.account_profiles.c.id).where(m.account_profiles.c.profile_id == m.profiles.c.id)))
    total = connection.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = connection.execute(query.order_by(m.profiles.c.created_at.desc(), m.profiles.c.id).offset(offset).limit(limit+1)).mappings().all()
    return {'items': [dict(r) for r in rows[:limit]], 'total': total, 'next_offset': offset+limit if len(rows) > limit else None}


@router.get('/profiles')
def own_profiles(user: Customer, offset: int = Query(0, ge=0), limit: int = Query(30, ge=1, le=100)):
    with get_engine().connect() as connection:
        return listing(connection, user, offset, limit)


@router.get('/admin/profiles')
def all_profiles(user: Admin, offset: int = Query(0, ge=0), limit: int = Query(30, ge=1, le=100),
                 q: str | None = Query(None, max_length=200),
                 gender: Literal['MALE','FEMALE','OTHER'] | None = None,
                 age_min: int | None = Query(None, ge=18, le=100), age_max: int | None = Query(None, ge=18, le=100),
                 location: str | None = Query(None, max_length=200), community: str | None = Query(None, max_length=100),
                 status: Literal['PENDING_VERIFICATION','APPROVED','REJECTED','INACTIVE'] | None = None,
                 unassociated_only: bool = False):
    if age_min is not None and age_max is not None and age_min > age_max:
        raise HTTPException(422, 'Minimum age must not exceed maximum age')
    with get_engine().connect() as connection:
        return listing(connection, user, offset, limit, q=q.strip() if q else None, gender=gender,
            age_min=age_min, age_max=age_max, location=location.strip() if location else None,
            community=community.strip() if community else None, status=status, unassociated_only=unassociated_only)


@router.post('/profiles', status_code=201)
def create_own(body: ProfileData, user: Customer):
    rate_limit('profile-create', user['id'], 20, 3600)
    with get_engine().begin() as connection:
        return create(connection, body, user)


@router.post('/admin/profiles', status_code=201)
def create_manual(body: AdminCreate, user: Admin):
    with get_engine().begin() as connection:
        return create(connection, body, user, administrator=True)


@router.get('/profiles/{profile_id}')
def get_profile(profile_id: UUID, user: User):
    with get_engine().connect() as connection:
        return details(connection, access(connection, profile_id, user), user)


@router.put('/profiles/{profile_id}')
def edit_profile(profile_id: UUID, body: EditProfile, user: User):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        profile = access(connection, profile_id, user, locked=True)
        expected(profile, body.version)
        editable(profile, user)
        connection.execute(update(m.profiles).where(m.profiles.c.id == profile_id).values(
            **body.model_dump(exclude={'education', 'family', 'preferences', 'version'})))
        for name, table in SECTIONS.items():
            connection.execute(pg_insert(table).values(profile_id=profile_id, **getattr(body, name).model_dump())
                .on_conflict_do_update(index_elements=['profile_id'], set_=getattr(body, name).model_dump()))
        changed(connection, profile, user, 'PROFILE_EDITED')
        return details(connection, access(connection, profile_id, user), user)


@router.put('/admin/profiles/{profile_id}/account')
def associate(profile_id: UUID, body: Association, user: Admin):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        profile = access(connection, profile_id, user, locked=True)
        expected(profile, body.version)
        owner = customer_id(connection, body.email) if body.email else None
        cancel_affected(connection,user['id'],'Profile account association changed',profile_id=profile_id)
        connection.execute(delete(m.account_profiles).where(m.account_profiles.c.profile_id == profile_id))
        if owner:
            connection.execute(insert(m.account_profiles).values(profile_id=profile_id, account_id=owner))
        connection.execute(update(m.profiles).where(m.profiles.c.id == profile_id).values(version=profile['version']+1))
        audit(connection, user, 'PROFILE_ACCOUNT_ASSOCIATED', profile_id, {'account_id': str(owner) if owner else None})
        return details(connection, access(connection, profile_id, user), user)


@router.put('/admin/profiles/{profile_id}/verification')
def verify_profile(profile_id: UUID, body: Verification, user: Admin):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        profile = access(connection, profile_id, user, locked=True)
        expected(profile, body.version)
        cancel_affected(connection,user['id'],'Profile verification or activation changed',profile_id=profile_id)
        connection.execute(update(m.profiles).where(m.profiles.c.id == profile_id).values(
            status=body.status, version=profile['version']+1, verification_note=body.note,
            verified_by=UUID(user['id']) if body.status in ('APPROVED', 'REJECTED') else None))
        audit(connection, user, 'PROFILE_STATUS_CHANGED', profile_id, {'from': profile['status'], 'to': body.status})
        notify(connection, profile_id, 'PROFILE_' + ('SUBMITTED' if body.status == 'PENDING_VERIFICATION' else body.status),
               'Your profile status is now ' + body.status.replace('_', ' ').lower() + '.')
        return details(connection, access(connection, profile_id, user), user)
