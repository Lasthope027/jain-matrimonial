"""Shared PostgreSQL schema. All data access will be mediated by the API."""
import uuid
from sqlalchemy import (Table, Column, String, Text, Integer, Boolean, Date, DateTime,
                        Numeric, ForeignKey, CheckConstraint, UniqueConstraint,
                        Uuid, JSON, Index, text)
from app.db import Base

metadata = Base.metadata


def table(name, *columns):
    return Table(name, metadata,
        Column('id', Uuid, primary_key=True, default=uuid.uuid4, server_default=text('gen_random_uuid()')),
        Column('created_at', DateTime(timezone=True), nullable=False, server_default=text('CURRENT_TIMESTAMP')),
        Column('updated_at', DateTime(timezone=True), nullable=False, server_default=text('CURRENT_TIMESTAMP')),
        *columns)


def ref(name, target, nullable=False):
    return Column(name, Uuid, ForeignKey(target + '.id', ondelete='RESTRICT'), nullable=nullable, index=True)


users = table('users', Column('email', String(254), nullable=False, unique=True),
    Column('version', Integer, nullable=False, server_default='1'),
    Column('email_verified_at', DateTime(timezone=True)),
    CheckConstraint('version > 0', name='ck_user_version'),
    Column('password_hash', Text), Column('active', Boolean, nullable=False, server_default=text('true')),
    CheckConstraint('email = lower(email)', name='ck_users_normalized_email'))
roles = table('roles', Column('name', String(20), nullable=False, unique=True),
    CheckConstraint("name IN ('CUSTOMER', 'ADMINISTRATOR')", name='ck_two_roles'))
user_roles = table('user_roles', ref('user_id', 'users'), ref('role_id', 'roles'),
    UniqueConstraint('user_id', name='uq_one_role_per_user'))
profiles = table('matrimonial_profiles',
    Column('version', Integer, nullable=False, server_default='1'),
    Column('sub_community', String(100)),
    CheckConstraint('version > 0', name='ck_profile_version'),
    Column('full_name', String(200), nullable=False, index=True),
    Column('gender', String(30), nullable=False), Column('date_of_birth', Date, nullable=False, index=True),
    Column('height_cm', Integer), Column('marital_status', String(40)),
    Column('community', String(100), index=True), Column('mother_tongue', String(80)),
    Column('current_location', String(200), index=True), Column('native_place', String(200)),
    Column('status', String(30), nullable=False, server_default='PENDING_VERIFICATION', index=True),
    ref('created_by', 'users'), ref('verified_by', 'users', True), Column('verification_note', Text),
    CheckConstraint("status IN ('PENDING_VERIFICATION','APPROVED','REJECTED','INACTIVE')", name='ck_profile_status'),
    CheckConstraint('height_cm IS NULL OR height_cm BETWEEN 50 AND 300', name='ck_profile_height'))
account_profiles = table('account_profile_relationships', ref('account_id', 'users'), ref('profile_id', 'matrimonial_profiles'),
    UniqueConstraint('profile_id', name='uq_profile_account'))
education = table('education_details', ref('profile_id', 'matrimonial_profiles'),
    Column('qualification', String(200)), Column('college', String(200)), Column('profession', String(200)),
    Column('company', String(200)), Column('employment_location', String(200)), Column('annual_income', Numeric(14, 2)),
    UniqueConstraint('profile_id'), CheckConstraint('annual_income IS NULL OR annual_income >= 0', name='ck_income'))
family = table('family_details', ref('profile_id', 'matrimonial_profiles'),
    *(Column(n, String(200)) for n in ('father_name','father_occupation','mother_name','mother_occupation','family_location')),
    Column('siblings', Integer), Column('additional_information', Text), UniqueConstraint('profile_id'),
    CheckConstraint('siblings IS NULL OR siblings >= 0', name='ck_siblings'))
preferences = table('partner_preferences', ref('profile_id', 'matrimonial_profiles'),
    Column('age_min', Integer), Column('age_max', Integer), Column('height_min_cm', Integer), Column('height_max_cm', Integer),
    *(Column(n, JSON) for n in ('locations','education','professions','communities','marital_statuses')),
    Column('additional_expectations', Text), UniqueConstraint('profile_id'),
    CheckConstraint('(age_min IS NULL OR age_min >= 18) AND (age_max IS NULL OR age_max >= 18) AND (age_min IS NULL OR age_max IS NULL OR age_min <= age_max)', name='ck_age_preference'),
    CheckConstraint('(height_min_cm IS NULL OR height_min_cm BETWEEN 50 AND 300) AND (height_max_cm IS NULL OR height_max_cm BETWEEN 50 AND 300) AND (height_min_cm IS NULL OR height_max_cm IS NULL OR height_min_cm <= height_max_cm)', name='ck_height_preference'))
documents = table('documents', ref('profile_id', 'matrimonial_profiles'), ref('uploaded_by', 'users'),
    Column('deleted_at', DateTime(timezone=True)),
    Column('storage_key', String(255), nullable=False, unique=True), Column('original_name', String(255), nullable=False),
    Column('media_type', String(80), nullable=False), Column('size_bytes', Integer, nullable=False),
    Column('sha256', String(64), nullable=False), Column('kind', String(20), nullable=False),
    CheckConstraint('size_bytes > 0 AND size_bytes <= 10485760', name='ck_document_size'),
    CheckConstraint("media_type IN ('application/pdf','image/jpeg','image/png')", name='ck_document_type'),
    CheckConstraint("kind IN ('PHOTO','BIODATA')", name='ck_document_kind'))
proposals = table('proposals', ref('profile_a_id', 'matrimonial_profiles'), ref('profile_b_id', 'matrimonial_profiles'),
    Column('version', Integer, nullable=False, server_default='1'),
    ref('account_a_id','users',True), ref('account_b_id','users',True),
    Column('profile_a_version',Integer), Column('profile_b_version',Integer),
    Column('profile_a_name',String(200)), Column('profile_b_name',String(200)),
    Column('preview_a',JSON), Column('preview_b',JSON),
    Column('closed_at',DateTime(timezone=True)), ref('closed_by','users',True), Column('closure_reason',Text),
    CheckConstraint('version > 0',name='ck_proposal_version'),
    CheckConstraint('account_a_id IS NULL OR account_b_id IS NULL OR account_a_id <> account_b_id',name='ck_distinct_proposal_accounts'),
    ref('created_by', 'users'), Column('status', String(30), nullable=False, server_default='PENDING', index=True),
    CheckConstraint('profile_a_id < profile_b_id', name='ck_ordered_distinct_pair'),
    CheckConstraint("status IN ('PENDING','REJECTED','MUTUALLY_ACCEPTED','CANCELLED')", name='ck_proposal_status'))
Index('uq_active_proposal_pair', proposals.c.profile_a_id, proposals.c.profile_b_id, unique=True,
      postgresql_where=proposals.c.status.in_(['PENDING','MUTUALLY_ACCEPTED']))
responses = table('proposal_responses', ref('proposal_id', 'proposals'), ref('profile_id', 'matrimonial_profiles'),
    ref('responded_by', 'users'), Column('response', String(10), nullable=False),
    UniqueConstraint('proposal_id','profile_id'), CheckConstraint("response IN ('ACCEPTED','REJECTED')", name='ck_response'))
sharing = table('biodata_sharing_records', ref('proposal_id', 'proposals'), ref('document_id', 'documents'),
    ref('recipient_account_id','users',True), Column('document_sha256',String(64)),
    Column('revoked_at',DateTime(timezone=True)), ref('revoked_by','users',True),
    ref('recipient_profile_id', 'matrimonial_profiles'), ref('authorised_by', 'users'),
    UniqueConstraint('proposal_id','document_id','recipient_profile_id'))
notifications = table('notifications', ref('user_id', 'users'), Column('event', String(60), nullable=False),
    ref('profile_id','matrimonial_profiles',True),
    Column('message', Text, nullable=False), Column('read_at', DateTime(timezone=True)), ref('proposal_id','proposals',True))
audit = table('audit_logs', ref('actor_id', 'users', True), Column('action', String(100), nullable=False),
    Column('entity_type', String(80), nullable=False), Column('entity_id', Uuid), Column('details', JSON))
otp = table('otp_verifications', Column('email', String(254), nullable=False, index=True),
    Column('code_hash', Text, nullable=False), Column('expires_at', DateTime(timezone=True), nullable=False),
    Column('attempts', Integer, nullable=False, server_default='0'), Column('consumed_at', DateTime(timezone=True)),
    Column('resend_after', DateTime(timezone=True), nullable=False),
    CheckConstraint('attempts BETWEEN 0 AND 5', name='ck_otp_attempts'))

sessions = table('auth_sessions', ref('user_id', 'users'),
    Column('access_hash', String(64), nullable=False, unique=True),
    Column('refresh_hash', String(64), nullable=False, unique=True),
    Column('access_expires_at', DateTime(timezone=True), nullable=False),
    Column('refresh_expires_at', DateTime(timezone=True), nullable=False),
    Column('revoked_at', DateTime(timezone=True)),
    CheckConstraint('access_expires_at <= refresh_expires_at', name='ck_session_expiry'))
rate_limits = table('auth_rate_limits', Column('key_hash', String(64), nullable=False, unique=True),
    Column('window_start', DateTime(timezone=True), nullable=False),
    Column('request_count', Integer, nullable=False),
    CheckConstraint('request_count > 0', name='ck_rate_count'))

Index('ix_users_created_at', users.c.created_at)
Index('ix_matrimonial_profiles_created_at', profiles.c.created_at)
Index('ix_matrimonial_profiles_gender', profiles.c.gender)
Index('ix_audit_logs_created_at', audit.c.created_at)
Index('ix_proposals_created_at',proposals.c.created_at)
Index('ix_notifications_user_created',notifications.c.user_id,notifications.c.created_at)
