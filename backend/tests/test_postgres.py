"""Run only against a disposable migrated database: TEST_DATABASE_URL=postgresql+psycopg://..."""
import os
import uuid
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError


@pytest.mark.skipif(not os.getenv('TEST_DATABASE_URL'), reason='Disposable PostgreSQL not configured')
def test_constraints_and_update_trigger():
    engine = create_engine(os.environ['TEST_DATABASE_URL'])
    with engine.connect() as connection:
        transaction = connection.begin()
        try:
            assert set(connection.execute(text('SELECT name FROM roles')).scalars()) == {'CUSTOMER', 'ADMINISTRATOR'}
            with pytest.raises(IntegrityError), connection.begin_nested():
                connection.execute(text("INSERT INTO roles (name) VALUES ('MANAGER')"))
            user_id = uuid.uuid4()
            connection.execute(text('INSERT INTO users (id, email) VALUES (:id, :email)'),
                               {'id': user_id, 'email': f'{user_id}@example.test'})
            with pytest.raises(IntegrityError), connection.begin_nested():
                connection.execute(text('INSERT INTO otp_verifications (email, code_hash, expires_at, resend_after, attempts) VALUES (:email, :hash, now(), now(), 6)'),
                                   {'email': 'test@example.test', 'hash': 'not-a-real-otp'})
            connection.execute(text("UPDATE users SET updated_at = '2000-01-01' WHERE id = :id"), {'id': user_id})
            assert connection.execute(text('SELECT EXTRACT(YEAR FROM updated_at) FROM users WHERE id = :id'), {'id': user_id}).scalar() > 2000
        finally:
            transaction.rollback()
    engine.dispose()
