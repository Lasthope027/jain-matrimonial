"""Initial schema, exactly two roles, and automatic update timestamps."""
import importlib.util
from pathlib import Path
from alembic import op
import sqlalchemy as sa

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def snapshot():
    spec = importlib.util.spec_from_file_location('schema_0001', Path(__file__).parents[1] / 'schema_0001.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.metadata


def upgrade():
    metadata = snapshot()
    metadata.create_all(op.get_bind(), checkfirst=False)
    op.execute("INSERT INTO roles (name) VALUES ('CUSTOMER'), ('ADMINISTRATOR')")
    op.execute('''CREATE FUNCTION touch_updated_at() RETURNS trigger AS $$
    BEGIN NEW.updated_at = CURRENT_TIMESTAMP; RETURN NEW; END;
    $$ LANGUAGE plpgsql''')
    for name in metadata.tables:
        op.execute(sa.text(f'CREATE TRIGGER touch_updated_at BEFORE UPDATE ON {name} '
                           'FOR EACH ROW EXECUTE FUNCTION touch_updated_at()'))


def downgrade():
    snapshot().drop_all(op.get_bind(), checkfirst=False)
    op.execute('DROP FUNCTION touch_updated_at()')
