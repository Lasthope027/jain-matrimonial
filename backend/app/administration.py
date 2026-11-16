from typing import Annotated
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, insert, update, func, exists, or_
from app import models as m
from app.auth import require_role, EmailInput, lock, secret, now
from app.security import keyed_hash
from app.db import get_engine
from app.workflow import lock_workflow,cancel_affected

router = APIRouter(prefix='/api/v1/admin', tags=['administration'])
Admin = Annotated[dict, Depends(require_role('ADMINISTRATOR'))]


def customers_query():
    return select(m.users.c.id, m.users.c.email, m.users.c.active, m.users.c.version,
        m.users.c.email_verified_at, m.users.c.created_at, m.users.c.updated_at).select_from(
        m.users.join(m.user_roles, m.user_roles.c.user_id == m.users.c.id)
        .join(m.roles, m.user_roles.c.role_id == m.roles.c.id)).where(m.roles.c.name == 'CUSTOMER')


def customer(connection, customer_id, *, locked=False):
    query = customers_query().where(m.users.c.id == customer_id)
    if locked:
        query = query.with_for_update(of=m.users)
    row = connection.execute(query).mappings().first()
    if row is None:
        raise HTTPException(404, 'Customer not found')
    return dict(row)


def customer_details(connection, customer_id):
    result = customer(connection, customer_id)
    result['profiles'] = [dict(row) for row in connection.execute(select(
        m.profiles.c.id, m.profiles.c.full_name, m.profiles.c.status, m.profiles.c.version)
        .join(m.account_profiles, m.account_profiles.c.profile_id == m.profiles.c.id)
        .where(m.account_profiles.c.account_id == customer_id).order_by(m.profiles.c.created_at.desc())).mappings()]
    return result


def audit(connection, user, action, customer_id, details=None):
    connection.execute(insert(m.audit).values(actor_id=UUID(user['id']), action=action,
        entity_type='customer', entity_id=customer_id, details=details))


@router.get('/dashboard')
def dashboard(user: Admin):
    # Multiple aggregates describe the same committed database snapshot.
    with get_engine().connect().execution_options(isolation_level='REPEATABLE READ') as connection:
        with connection.begin():
            p = m.profiles
            result = dict(connection.execute(select(func.count().label('total_profiles'),
                *(func.count().filter(p.c.status == status).label(name) for name, status in [
                    ('pending_verification','PENDING_VERIFICATION'),('approved_profiles','APPROVED'),
                    ('rejected_profiles','REJECTED'),('inactive_profiles','INACTIVE')])).select_from(p)).mappings().one())
            proposals = connection.execute(select(m.proposals.c.status, func.count()).group_by(m.proposals.c.status)).all()
            counts = dict(proposals)
            result['active_proposals'] = counts.get('PENDING',0) + counts.get('MUTUALLY_ACCEPTED',0)
            result['mutually_accepted_proposals'] = counts.get('MUTUALLY_ACCEPTED',0)
            response_counts = select(m.responses.c.proposal_id, func.count().label('responses')).join(
                m.proposals, m.responses.c.proposal_id == m.proposals.c.id).where(
                m.responses.c.profile_id.in_([m.proposals.c.profile_a_id, m.proposals.c.profile_b_id]))
            response_counts = response_counts.group_by(m.responses.c.proposal_id).subquery()
            result['pending_responses'] = connection.execute(select(func.coalesce(func.sum(
                2-func.coalesce(response_counts.c.responses,0)),0)).select_from(m.proposals.outerjoin(response_counts,
                response_counts.c.proposal_id == m.proposals.c.id)).where(m.proposals.c.status == 'PENDING')).scalar_one()
            result['total_customers'] = connection.execute(select(func.count()).select_from(customers_query().subquery())).scalar_one()
            result['active_customers'] = connection.execute(select(func.count()).select_from(customers_query().where(m.users.c.active.is_(True)).subquery())).scalar_one()
            result['unassociated_profiles'] = connection.execute(select(func.count()).select_from(p).where(
                ~exists(select(m.account_profiles.c.id).where(m.account_profiles.c.profile_id == p.c.id)))).scalar_one()
            result['generated_at'] = now()
            return result


@router.get('/customers')
def list_customers(user: Admin, q: str | None = Query(None, max_length=254), active: bool | None = None,
                   offset: int = Query(0, ge=0), limit: int = Query(30, ge=1, le=100)):
    with get_engine().connect() as connection:
        query = customers_query()
        if q and q.strip():
            query = query.where(m.users.c.email.icontains(q.strip(), autoescape=True))
        if active is not None:
            query = query.where(m.users.c.active.is_(active))
        total = connection.execute(select(func.count()).select_from(query.subquery())).scalar_one()
        count = select(func.count()).select_from(m.account_profiles).where(m.account_profiles.c.account_id == m.users.c.id).scalar_subquery()
        rows = connection.execute(query.add_columns(count.label('profile_count'))
            .order_by(m.users.c.created_at.desc(),m.users.c.id).offset(offset).limit(limit+1)).mappings().all()
        return {'items':[dict(row) for row in rows[:limit]],'total':total,'next_offset':offset+limit if len(rows)>limit else None}


@router.post('/customers', status_code=201)
def create_customer(body: EmailInput, user: Admin):
    with get_engine().begin() as connection:
        # Same lock as OTP login and local administrator provisioning.
        lock(connection, keyed_hash(secret(),'otp:'+body.email))
        if connection.execute(select(m.users.c.id).where(m.users.c.email == body.email)).first():
            raise HTTPException(409,'An account already exists for this email')
        user_id = connection.execute(insert(m.users).values(email=body.email).returning(m.users.c.id)).scalar_one()
        role_id = connection.execute(select(m.roles.c.id).where(m.roles.c.name == 'CUSTOMER')).scalar_one()
        connection.execute(insert(m.user_roles).values(user_id=user_id, role_id=role_id))
        connection.execute(insert(m.notifications).values(user_id=user_id,event='REGISTRATION_COMPLETED',
            message='The consultancy created your account. Verify your email with a sign-in code to access it.'))
        audit(connection,user,'CUSTOMER_CREATED',user_id)
        return customer_details(connection,user_id)


@router.get('/customers/{customer_id}')
def get_customer(customer_id: UUID, user: Admin):
    with get_engine().connect() as connection:
        return customer_details(connection,customer_id)


class Activation(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    version: int = Field(ge=1)
    active: bool


@router.put('/customers/{customer_id}/activation')
def activate(customer_id: UUID, body: Activation, user: Admin):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        row = customer(connection,customer_id)
        lock(connection,keyed_hash(secret(),'otp:'+row['email']))
        row = customer(connection,customer_id,locked=True)
        if row['version'] != body.version:
            raise HTTPException(409,'This customer account has changed. Reload it before saving.')
        if row['active'] != body.active:
            connection.execute(update(m.users).where(m.users.c.id == customer_id).values(active=body.active,version=row['version']+1))
            if not body.active:
                cancel_affected(connection,user['id'],'Customer account deactivated',account_id=customer_id)
                connection.execute(update(m.sessions).where(m.sessions.c.user_id == customer_id,m.sessions.c.revoked_at.is_(None)).values(revoked_at=now()))
                connection.execute(update(m.otp).where(m.otp.c.email == row['email'],m.otp.c.consumed_at.is_(None)).values(consumed_at=now()))
            audit(connection,user,'CUSTOMER_ACTIVATED' if body.active else 'CUSTOMER_DEACTIVATED',customer_id,
                {'from_active':row['active'],'to_active':body.active})
        return customer_details(connection,customer_id)


@router.get('/audit-logs')
def audit_logs(user: Admin, q: str | None = Query(None,max_length=100), actor_id: UUID | None = None,
               offset: int = Query(0,ge=0), limit: int = Query(30,ge=1,le=100)):
    with get_engine().connect() as connection:
        query = select(m.audit.c.id,m.audit.c.created_at,m.audit.c.actor_id,m.users.c.email.label('actor_email'),
            m.audit.c.action,m.audit.c.entity_type,m.audit.c.entity_id,m.audit.c.details).outerjoin(m.users,m.audit.c.actor_id == m.users.c.id)
        if q and q.strip():
            query = query.where(or_(m.audit.c.action.icontains(q.strip(),autoescape=True),
                m.audit.c.entity_type.icontains(q.strip(),autoescape=True),m.users.c.email.icontains(q.strip(),autoescape=True)))
        if actor_id:
            query = query.where(m.audit.c.actor_id == actor_id)
        total = connection.execute(select(func.count()).select_from(query.subquery())).scalar_one()
        rows = connection.execute(query.order_by(m.audit.c.created_at.desc(),m.audit.c.id).offset(offset).limit(limit+1)).mappings().all()
        return {'items':[dict(row) for row in rows[:limit]],'total':total,'next_offset':offset+limit if len(rows)>limit else None}
