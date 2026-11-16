"""Serialise consent-affecting transactions across backend workers.

A short global transaction lock is appropriate for this consultancy MVP. Every
profile/account mutation and proposal operation takes it BEFORE row locks.
"""
from uuid import UUID
from sqlalchemy import select,update,insert,or_,text
from app import models as m
from app.auth import now

ACTIVE=('PENDING','MUTUALLY_ACCEPTED')


def lock_workflow(connection):
    connection.execute(text('SELECT pg_advisory_xact_lock(:key)'),{'key':780541205})


def notify_parties(connection,proposal,event,message):
    for account in {proposal['account_a_id'],proposal['account_b_id']} - {None}:
        connection.execute(insert(m.notifications).values(user_id=account,event=event,message=message,proposal_id=proposal['id']))


def audit(connection,actor,action,proposal_id,details=None):
    connection.execute(insert(m.audit).values(actor_id=UUID(actor) if isinstance(actor,str) else actor,
        action=action,entity_type='proposal',entity_id=proposal_id,details=details))


def cancel(connection,proposal,actor,reason):
    if proposal['status'] not in ACTIVE:
        return
    current=now()
    actor=UUID(actor) if isinstance(actor,str) else actor
    connection.execute(update(m.proposals).where(m.proposals.c.id==proposal['id']).values(
        status='CANCELLED',version=proposal['version']+1,closed_at=current,closed_by=actor,closure_reason=reason))
    connection.execute(update(m.sharing).where(m.sharing.c.proposal_id==proposal['id'],m.sharing.c.revoked_at.is_(None))
        .values(revoked_at=current,revoked_by=actor))
    audit(connection,actor,'PROPOSAL_CANCELLED',proposal['id'],{'reason':reason})
    notify_parties(connection,proposal,'PROPOSAL_CANCELLED','The consultancy proposal was closed. Any shared-file access has ended.')


def cancel_affected(connection,actor,reason,*,profile_id=None,account_id=None):
    lock_workflow(connection)
    condition=or_(m.proposals.c.profile_a_id==profile_id,m.proposals.c.profile_b_id==profile_id) if profile_id else or_(
        m.proposals.c.account_a_id==account_id,m.proposals.c.account_b_id==account_id)
    rows=connection.execute(select(m.proposals).where(condition,m.proposals.c.status.in_(ACTIVE))
        .order_by(m.proposals.c.id).with_for_update()).mappings().all()
    for proposal in rows:
        cancel(connection,proposal,actor,reason)
