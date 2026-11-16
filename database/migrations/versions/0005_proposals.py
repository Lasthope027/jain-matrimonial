"""Consent snapshots, safe cancellation and auditable document authorisation."""
from alembic import op
import sqlalchemy as sa

revision='0005'
down_revision='0004'
branch_labels=None
depends_on=None


def upgrade():
    op.add_column('proposals',sa.Column('version',sa.Integer(),nullable=False,server_default='1'))
    for name in ('account_a_id','account_b_id','closed_by'):
        op.add_column('proposals',sa.Column(name,sa.Uuid(),sa.ForeignKey('users.id',ondelete='RESTRICT')))
        op.create_index('ix_proposals_'+name,'proposals',[name])
    for name in ('profile_a_version','profile_b_version'):
        op.add_column('proposals',sa.Column(name,sa.Integer()))
    for name in ('profile_a_name','profile_b_name'):
        op.add_column('proposals',sa.Column(name,sa.String(200)))
    for name in ('preview_a','preview_b'):
        op.add_column('proposals',sa.Column(name,sa.JSON()))
    op.add_column('proposals',sa.Column('closed_at',sa.DateTime(timezone=True)))
    op.add_column('proposals',sa.Column('closure_reason',sa.Text()))
    op.create_check_constraint('ck_proposal_version','proposals','version > 0')
    op.create_check_constraint('ck_distinct_proposal_accounts','proposals','account_a_id IS NULL OR account_b_id IS NULL OR account_a_id <> account_b_id')
    op.drop_constraint('ck_proposal_status','proposals',type_='check')
    op.create_check_constraint('ck_proposal_status','proposals',"status IN ('PENDING','REJECTED','MUTUALLY_ACCEPTED','CANCELLED')")
    op.drop_index('uq_active_proposal_pair',table_name='proposals')
    op.create_index('uq_active_proposal_pair','proposals',['profile_a_id','profile_b_id'],unique=True,
        postgresql_where=sa.text("status IN ('PENDING','MUTUALLY_ACCEPTED')"))
    op.create_index('ix_proposals_created_at','proposals',['created_at'])
    for name in ('recipient_account_id','revoked_by'):
        op.add_column('biodata_sharing_records',sa.Column(name,sa.Uuid(),sa.ForeignKey('users.id',ondelete='RESTRICT')))
        op.create_index('ix_biodata_sharing_records_'+name,'biodata_sharing_records',[name])
    op.add_column('biodata_sharing_records',sa.Column('document_sha256',sa.String(64)))
    op.add_column('biodata_sharing_records',sa.Column('revoked_at',sa.DateTime(timezone=True)))
    op.add_column('notifications',sa.Column('profile_id',sa.Uuid(),sa.ForeignKey('matrimonial_profiles.id',ondelete='RESTRICT')))
    op.create_index('ix_notifications_profile_id','notifications',['profile_id'])
    op.create_index('ix_notifications_user_created','notifications',['user_id','created_at'])
    # Earlier phases had no proposal workflow, so pre-existing rows cannot prove
    # version-bound consent. Preserve their audit/history, withdraw active access.
    op.execute("""INSERT INTO audit_logs (action,entity_type,entity_id,details)
        SELECT 'LEGACY_PROPOSAL_CLOSED','proposal',id,json_build_object('previous_status',status)
        FROM proposals WHERE status IN ('PENDING','MUTUALLY_ACCEPTED')""")
    op.execute("""UPDATE proposals SET status='CANCELLED',version=version+1,closed_at=now(),
        closure_reason='Legacy proposal requires fresh version-bound consent'
        WHERE status IN ('PENDING','MUTUALLY_ACCEPTED')""")
    op.execute('UPDATE biodata_sharing_records SET revoked_at=now() WHERE revoked_at IS NULL')


def downgrade():
    op.execute("UPDATE proposals SET status='REJECTED' WHERE status='CANCELLED'")
    op.drop_index('uq_active_proposal_pair',table_name='proposals')
    op.create_index('uq_active_proposal_pair','proposals',['profile_a_id','profile_b_id'],unique=True,postgresql_where=sa.text("status != 'REJECTED'"))
    op.drop_constraint('ck_proposal_status','proposals',type_='check')
    op.create_check_constraint('ck_proposal_status','proposals',"status IN ('PENDING','REJECTED','MUTUALLY_ACCEPTED')")
    for index in ('ix_notifications_user_created','ix_notifications_profile_id'):
        op.drop_index(index,table_name='notifications')
    op.drop_column('notifications','profile_id')
    for name in ('recipient_account_id','revoked_by'):
        op.drop_index('ix_biodata_sharing_records_'+name,table_name='biodata_sharing_records')
    for name in ('recipient_account_id','revoked_by','document_sha256','revoked_at'):
        op.drop_column('biodata_sharing_records',name)
    op.drop_index('ix_proposals_created_at',table_name='proposals')
    for name in ('account_a_id','account_b_id','closed_by'):
        op.drop_index('ix_proposals_'+name,table_name='proposals')
    op.drop_constraint('ck_distinct_proposal_accounts','proposals',type_='check')
    op.drop_constraint('ck_proposal_version','proposals',type_='check')
    for name in ('version','account_a_id','account_b_id','profile_a_version','profile_b_version','profile_a_name','profile_b_name',
                 'preview_a','preview_b','closed_at','closed_by','closure_reason'):
        op.drop_column('proposals',name)
