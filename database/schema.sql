BEGIN;

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- Running upgrade  -> 0001

CREATE TABLE users (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    email VARCHAR(254) NOT NULL,
    password_hash TEXT,
    active BOOLEAN DEFAULT true NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_users_normalized_email CHECK (email = lower(email)),
    UNIQUE (email)
);

CREATE TABLE roles (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name VARCHAR(20) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_two_roles CHECK (name IN ('CUSTOMER', 'ADMINISTRATOR')),
    UNIQUE (name)
);

CREATE TABLE otp_verifications (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    email VARCHAR(254) NOT NULL,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts INTEGER DEFAULT '0' NOT NULL,
    consumed_at TIMESTAMP WITH TIME ZONE,
    resend_after TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_otp_attempts CHECK (attempts BETWEEN 0 AND 5)
);

CREATE INDEX ix_otp_verifications_email ON otp_verifications (email);

CREATE TABLE user_roles (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id UUID NOT NULL,
    role_id UUID NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_one_role_per_user UNIQUE (user_id),
    FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY(role_id) REFERENCES roles (id) ON DELETE RESTRICT
);

CREATE INDEX ix_user_roles_user_id ON user_roles (user_id);

CREATE INDEX ix_user_roles_role_id ON user_roles (role_id);

CREATE TABLE matrimonial_profiles (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    gender VARCHAR(30) NOT NULL,
    date_of_birth DATE NOT NULL,
    height_cm INTEGER,
    marital_status VARCHAR(40),
    community VARCHAR(100),
    mother_tongue VARCHAR(80),
    current_location VARCHAR(200),
    native_place VARCHAR(200),
    status VARCHAR(30) DEFAULT 'PENDING_VERIFICATION' NOT NULL,
    created_by UUID NOT NULL,
    verified_by UUID,
    verification_note TEXT,
    PRIMARY KEY (id),
    CONSTRAINT ck_profile_status CHECK (status IN ('PENDING_VERIFICATION','APPROVED','REJECTED','INACTIVE')),
    CONSTRAINT ck_profile_height CHECK (height_cm IS NULL OR height_cm BETWEEN 50 AND 300),
    FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY(verified_by) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX ix_matrimonial_profiles_verified_by ON matrimonial_profiles (verified_by);

CREATE INDEX ix_matrimonial_profiles_status ON matrimonial_profiles (status);

CREATE INDEX ix_matrimonial_profiles_full_name ON matrimonial_profiles (full_name);

CREATE INDEX ix_matrimonial_profiles_community ON matrimonial_profiles (community);

CREATE INDEX ix_matrimonial_profiles_created_by ON matrimonial_profiles (created_by);

CREATE INDEX ix_matrimonial_profiles_date_of_birth ON matrimonial_profiles (date_of_birth);

CREATE INDEX ix_matrimonial_profiles_current_location ON matrimonial_profiles (current_location);

CREATE TABLE audit_logs (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    actor_id UUID,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(80) NOT NULL,
    entity_id UUID,
    details JSON,
    PRIMARY KEY (id),
    FOREIGN KEY(actor_id) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX ix_audit_logs_actor_id ON audit_logs (actor_id);

CREATE TABLE account_profile_relationships (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    account_id UUID NOT NULL,
    profile_id UUID NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_profile_account UNIQUE (profile_id),
    FOREIGN KEY(account_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT
);

CREATE INDEX ix_account_profile_relationships_account_id ON account_profile_relationships (account_id);

CREATE INDEX ix_account_profile_relationships_profile_id ON account_profile_relationships (profile_id);

CREATE TABLE education_details (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    profile_id UUID NOT NULL,
    qualification VARCHAR(200),
    college VARCHAR(200),
    profession VARCHAR(200),
    company VARCHAR(200),
    employment_location VARCHAR(200),
    annual_income NUMERIC(14, 2),
    PRIMARY KEY (id),
    UNIQUE (profile_id),
    CONSTRAINT ck_income CHECK (annual_income IS NULL OR annual_income >= 0),
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT
);

CREATE INDEX ix_education_details_profile_id ON education_details (profile_id);

CREATE TABLE family_details (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    profile_id UUID NOT NULL,
    father_name VARCHAR(200),
    father_occupation VARCHAR(200),
    mother_name VARCHAR(200),
    mother_occupation VARCHAR(200),
    family_location VARCHAR(200),
    siblings INTEGER,
    additional_information TEXT,
    PRIMARY KEY (id),
    UNIQUE (profile_id),
    CONSTRAINT ck_siblings CHECK (siblings IS NULL OR siblings >= 0),
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT
);

CREATE INDEX ix_family_details_profile_id ON family_details (profile_id);

CREATE TABLE partner_preferences (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    profile_id UUID NOT NULL,
    age_min INTEGER,
    age_max INTEGER,
    height_min_cm INTEGER,
    height_max_cm INTEGER,
    locations JSON,
    education JSON,
    professions JSON,
    communities JSON,
    marital_statuses JSON,
    additional_expectations TEXT,
    PRIMARY KEY (id),
    UNIQUE (profile_id),
    CONSTRAINT ck_age_preference CHECK ((age_min IS NULL OR age_min >= 18) AND (age_max IS NULL OR age_max >= 18) AND (age_min IS NULL OR age_max IS NULL OR age_min <= age_max)),
    CONSTRAINT ck_height_preference CHECK ((height_min_cm IS NULL OR height_min_cm BETWEEN 50 AND 300) AND (height_max_cm IS NULL OR height_max_cm BETWEEN 50 AND 300) AND (height_min_cm IS NULL OR height_max_cm IS NULL OR height_min_cm <= height_max_cm)),
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT
);

CREATE INDEX ix_partner_preferences_profile_id ON partner_preferences (profile_id);

CREATE TABLE documents (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    profile_id UUID NOT NULL,
    uploaded_by UUID NOT NULL,
    storage_key VARCHAR(255) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    media_type VARCHAR(80) NOT NULL,
    size_bytes INTEGER NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    kind VARCHAR(20) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_document_size CHECK (size_bytes > 0 AND size_bytes <= 10485760),
    CONSTRAINT ck_document_type CHECK (media_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT ck_document_kind CHECK (kind IN ('PHOTO','BIODATA')),
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT,
    FOREIGN KEY(uploaded_by) REFERENCES users (id) ON DELETE RESTRICT,
    UNIQUE (storage_key)
);

CREATE INDEX ix_documents_profile_id ON documents (profile_id);

CREATE INDEX ix_documents_uploaded_by ON documents (uploaded_by);

CREATE TABLE proposals (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    profile_a_id UUID NOT NULL,
    profile_b_id UUID NOT NULL,
    created_by UUID NOT NULL,
    status VARCHAR(30) DEFAULT 'PENDING' NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_ordered_distinct_pair CHECK (profile_a_id < profile_b_id),
    CONSTRAINT ck_proposal_status CHECK (status IN ('PENDING','REJECTED','MUTUALLY_ACCEPTED')),
    FOREIGN KEY(profile_a_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT,
    FOREIGN KEY(profile_b_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT,
    FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX ix_proposals_profile_b_id ON proposals (profile_b_id);

CREATE UNIQUE INDEX uq_active_proposal_pair ON proposals (profile_a_id, profile_b_id) WHERE status != 'REJECTED';

CREATE INDEX ix_proposals_created_by ON proposals (created_by);

CREATE INDEX ix_proposals_profile_a_id ON proposals (profile_a_id);

CREATE INDEX ix_proposals_status ON proposals (status);

CREATE TABLE proposal_responses (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    proposal_id UUID NOT NULL,
    profile_id UUID NOT NULL,
    responded_by UUID NOT NULL,
    response VARCHAR(10) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (proposal_id, profile_id),
    CONSTRAINT ck_response CHECK (response IN ('ACCEPTED','REJECTED')),
    FOREIGN KEY(proposal_id) REFERENCES proposals (id) ON DELETE RESTRICT,
    FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT,
    FOREIGN KEY(responded_by) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX ix_proposal_responses_proposal_id ON proposal_responses (proposal_id);

CREATE INDEX ix_proposal_responses_profile_id ON proposal_responses (profile_id);

CREATE INDEX ix_proposal_responses_responded_by ON proposal_responses (responded_by);

CREATE TABLE biodata_sharing_records (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    proposal_id UUID NOT NULL,
    document_id UUID NOT NULL,
    recipient_profile_id UUID NOT NULL,
    authorised_by UUID NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (proposal_id, document_id, recipient_profile_id),
    FOREIGN KEY(proposal_id) REFERENCES proposals (id) ON DELETE RESTRICT,
    FOREIGN KEY(document_id) REFERENCES documents (id) ON DELETE RESTRICT,
    FOREIGN KEY(recipient_profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT,
    FOREIGN KEY(authorised_by) REFERENCES users (id) ON DELETE RESTRICT
);

CREATE INDEX ix_biodata_sharing_records_proposal_id ON biodata_sharing_records (proposal_id);

CREATE INDEX ix_biodata_sharing_records_authorised_by ON biodata_sharing_records (authorised_by);

CREATE INDEX ix_biodata_sharing_records_document_id ON biodata_sharing_records (document_id);

CREATE INDEX ix_biodata_sharing_records_recipient_profile_id ON biodata_sharing_records (recipient_profile_id);

CREATE TABLE notifications (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id UUID NOT NULL,
    event VARCHAR(60) NOT NULL,
    message TEXT NOT NULL,
    read_at TIMESTAMP WITH TIME ZONE,
    proposal_id UUID,
    PRIMARY KEY (id),
    FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY(proposal_id) REFERENCES proposals (id) ON DELETE RESTRICT
);

CREATE INDEX ix_notifications_user_id ON notifications (user_id);

CREATE INDEX ix_notifications_proposal_id ON notifications (proposal_id);

INSERT INTO roles (name) VALUES ('CUSTOMER'), ('ADMINISTRATOR');

CREATE FUNCTION touch_updated_at() RETURNS trigger AS $$
    BEGIN NEW.updated_at = CURRENT_TIMESTAMP; RETURN NEW; END;
    $$ LANGUAGE plpgsql;

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON user_roles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON matrimonial_profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON account_profile_relationships FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON education_details FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON family_details FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON partner_preferences FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON proposals FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON proposal_responses FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON biodata_sharing_records FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON audit_logs FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON otp_verifications FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

INSERT INTO alembic_version (version_num) VALUES ('0001') RETURNING alembic_version.version_num;

-- Running upgrade 0001 -> 0002

CREATE TABLE auth_sessions (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id UUID NOT NULL,
    access_hash VARCHAR(64) NOT NULL,
    refresh_hash VARCHAR(64) NOT NULL,
    access_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    refresh_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id),
    CONSTRAINT ck_session_expiry CHECK (access_expires_at <= refresh_expires_at),
    FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE RESTRICT,
    UNIQUE (access_hash),
    UNIQUE (refresh_hash)
);

CREATE INDEX ix_auth_sessions_user_id ON auth_sessions (user_id);

CREATE TABLE auth_rate_limits (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    key_hash VARCHAR(64) NOT NULL,
    window_start TIMESTAMP WITH TIME ZONE NOT NULL,
    request_count INTEGER NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_rate_count CHECK (request_count > 0),
    UNIQUE (key_hash)
);

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON auth_sessions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON auth_rate_limits FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

UPDATE alembic_version SET version_num='0002' WHERE alembic_version.version_num = '0001';

-- Running upgrade 0002 -> 0003

ALTER TABLE matrimonial_profiles ADD COLUMN version INTEGER DEFAULT '1' NOT NULL;

ALTER TABLE matrimonial_profiles ADD CONSTRAINT ck_profile_version CHECK (version > 0);

ALTER TABLE matrimonial_profiles ADD COLUMN sub_community VARCHAR(100);

ALTER TABLE documents ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

UPDATE alembic_version SET version_num='0003' WHERE alembic_version.version_num = '0002';

-- Running upgrade 0003 -> 0004

ALTER TABLE users ADD COLUMN version INTEGER DEFAULT '1' NOT NULL;

ALTER TABLE users ADD CONSTRAINT ck_user_version CHECK (version > 0);

ALTER TABLE users ADD COLUMN email_verified_at TIMESTAMP WITH TIME ZONE;

UPDATE users SET email_verified_at = (
        SELECT min(created_at) FROM audit_logs WHERE actor_id = users.id
        AND action IN ('CUSTOMER_REGISTERED', 'CUSTOMER_LOGIN'))
        WHERE EXISTS (SELECT 1 FROM audit_logs WHERE actor_id = users.id
        AND action IN ('CUSTOMER_REGISTERED', 'CUSTOMER_LOGIN'));

CREATE INDEX ix_users_created_at ON users (created_at);

CREATE INDEX ix_matrimonial_profiles_created_at ON matrimonial_profiles (created_at);

CREATE INDEX ix_matrimonial_profiles_gender ON matrimonial_profiles (gender);

CREATE INDEX ix_audit_logs_created_at ON audit_logs (created_at);

UPDATE alembic_version SET version_num='0004' WHERE alembic_version.version_num = '0003';

-- Running upgrade 0004 -> 0005

ALTER TABLE proposals ADD COLUMN version INTEGER DEFAULT '1' NOT NULL;

ALTER TABLE proposals ADD COLUMN account_a_id UUID;

ALTER TABLE proposals ADD FOREIGN KEY(account_a_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX ix_proposals_account_a_id ON proposals (account_a_id);

ALTER TABLE proposals ADD COLUMN account_b_id UUID;

ALTER TABLE proposals ADD FOREIGN KEY(account_b_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX ix_proposals_account_b_id ON proposals (account_b_id);

ALTER TABLE proposals ADD COLUMN closed_by UUID;

ALTER TABLE proposals ADD FOREIGN KEY(closed_by) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX ix_proposals_closed_by ON proposals (closed_by);

ALTER TABLE proposals ADD COLUMN profile_a_version INTEGER;

ALTER TABLE proposals ADD COLUMN profile_b_version INTEGER;

ALTER TABLE proposals ADD COLUMN profile_a_name VARCHAR(200);

ALTER TABLE proposals ADD COLUMN profile_b_name VARCHAR(200);

ALTER TABLE proposals ADD COLUMN preview_a JSON;

ALTER TABLE proposals ADD COLUMN preview_b JSON;

ALTER TABLE proposals ADD COLUMN closed_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE proposals ADD COLUMN closure_reason TEXT;

ALTER TABLE proposals ADD CONSTRAINT ck_proposal_version CHECK (version > 0);

ALTER TABLE proposals ADD CONSTRAINT ck_distinct_proposal_accounts CHECK (account_a_id IS NULL OR account_b_id IS NULL OR account_a_id <> account_b_id);

ALTER TABLE proposals DROP CONSTRAINT ck_proposal_status;

ALTER TABLE proposals ADD CONSTRAINT ck_proposal_status CHECK (status IN ('PENDING','REJECTED','MUTUALLY_ACCEPTED','CANCELLED'));

DROP INDEX uq_active_proposal_pair;

CREATE UNIQUE INDEX uq_active_proposal_pair ON proposals (profile_a_id, profile_b_id) WHERE status IN ('PENDING','MUTUALLY_ACCEPTED');

CREATE INDEX ix_proposals_created_at ON proposals (created_at);

ALTER TABLE biodata_sharing_records ADD COLUMN recipient_account_id UUID;

ALTER TABLE biodata_sharing_records ADD FOREIGN KEY(recipient_account_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX ix_biodata_sharing_records_recipient_account_id ON biodata_sharing_records (recipient_account_id);

ALTER TABLE biodata_sharing_records ADD COLUMN revoked_by UUID;

ALTER TABLE biodata_sharing_records ADD FOREIGN KEY(revoked_by) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX ix_biodata_sharing_records_revoked_by ON biodata_sharing_records (revoked_by);

ALTER TABLE biodata_sharing_records ADD COLUMN document_sha256 VARCHAR(64);

ALTER TABLE biodata_sharing_records ADD COLUMN revoked_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE notifications ADD COLUMN profile_id UUID;

ALTER TABLE notifications ADD FOREIGN KEY(profile_id) REFERENCES matrimonial_profiles (id) ON DELETE RESTRICT;

CREATE INDEX ix_notifications_profile_id ON notifications (profile_id);

CREATE INDEX ix_notifications_user_created ON notifications (user_id, created_at);

INSERT INTO audit_logs (action,entity_type,entity_id,details)
        SELECT 'LEGACY_PROPOSAL_CLOSED','proposal',id,json_build_object('previous_status',status)
        FROM proposals WHERE status IN ('PENDING','MUTUALLY_ACCEPTED');

UPDATE proposals SET status='CANCELLED',version=version+1,closed_at=now(),
        closure_reason='Legacy proposal requires fresh version-bound consent'
        WHERE status IN ('PENDING','MUTUALLY_ACCEPTED');

UPDATE biodata_sharing_records SET revoked_at=now() WHERE revoked_at IS NULL;

UPDATE alembic_version SET version_num='0005' WHERE alembic_version.version_num = '0004';

COMMIT;
