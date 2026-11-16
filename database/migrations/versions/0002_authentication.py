"""Revocable sessions and cross-worker authentication rate limits."""
from alembic import op
import sqlalchemy as sa

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def common():
    return [sa.Column('id', sa.Uuid(), primary_key=True, server_default=sa.text('gen_random_uuid()')),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('CURRENT_TIMESTAMP'))]


def upgrade():
    op.create_table('auth_sessions', *common(),
        sa.Column('user_id', sa.Uuid(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('access_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('refresh_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('access_expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('refresh_expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True)),
        sa.CheckConstraint('access_expires_at <= refresh_expires_at', name='ck_session_expiry'))
    op.create_index('ix_auth_sessions_user_id', 'auth_sessions', ['user_id'])
    op.create_table('auth_rate_limits', *common(),
        sa.Column('key_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('window_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('request_count', sa.Integer(), nullable=False),
        sa.CheckConstraint('request_count > 0', name='ck_rate_count'))
    for name in ('auth_sessions', 'auth_rate_limits'):
        op.execute(f'CREATE TRIGGER touch_updated_at BEFORE UPDATE ON {name} FOR EACH ROW EXECUTE FUNCTION touch_updated_at()')


def downgrade():
    op.drop_table('auth_rate_limits')
    op.drop_table('auth_sessions')
