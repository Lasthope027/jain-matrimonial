"""Profile concurrency, sub-community and document withdrawal."""
from alembic import op
import sqlalchemy as sa

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('matrimonial_profiles', sa.Column('version', sa.Integer(), nullable=False, server_default='1'))
    op.create_check_constraint('ck_profile_version', 'matrimonial_profiles', 'version > 0')
    op.add_column('matrimonial_profiles', sa.Column('sub_community', sa.String(100)))
    op.add_column('documents', sa.Column('deleted_at', sa.DateTime(timezone=True)))


def downgrade():
    op.drop_column('documents', 'deleted_at')
    op.drop_column('matrimonial_profiles', 'sub_community')
    op.drop_constraint('ck_profile_version', 'matrimonial_profiles', type_='check')
    op.drop_column('matrimonial_profiles', 'version')
