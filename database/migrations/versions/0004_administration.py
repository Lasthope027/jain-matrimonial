"""Customer management concurrency, email verification and list indexes."""
from alembic import op
import sqlalchemy as sa

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column('version', sa.Integer(), nullable=False, server_default='1'))
    op.create_check_constraint('ck_user_version', 'users', 'version > 0')
    op.add_column('users', sa.Column('email_verified_at', sa.DateTime(timezone=True)))
    # OTP consumption also occurs on invalidation; only successful login audit
    # records are evidence of verification for existing accounts.
    op.execute("""UPDATE users SET email_verified_at = (
        SELECT min(created_at) FROM audit_logs WHERE actor_id = users.id
        AND action IN ('CUSTOMER_REGISTERED', 'CUSTOMER_LOGIN'))
        WHERE EXISTS (SELECT 1 FROM audit_logs WHERE actor_id = users.id
        AND action IN ('CUSTOMER_REGISTERED', 'CUSTOMER_LOGIN'))""")
    for table, column in [('users','created_at'),('matrimonial_profiles','created_at'),
                          ('matrimonial_profiles','gender'),('audit_logs','created_at')]:
        op.create_index(f'ix_{table}_{column}', table, [column])


def downgrade():
    for table, column in [('users','created_at'),('matrimonial_profiles','created_at'),
                          ('matrimonial_profiles','gender'),('audit_logs','created_at')]:
        op.drop_index(f'ix_{table}_{column}', table_name=table)
    op.drop_column('users', 'email_verified_at')
    op.drop_constraint('ck_user_version', 'users', type_='check')
    op.drop_column('users', 'version')
