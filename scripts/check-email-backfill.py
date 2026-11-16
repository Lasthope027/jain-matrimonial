"""Exercise migration 0004 backfill only on an empty disposable *_test database.

Run with seed at revision 0003, upgrade to head, then verify-cleanup.
"""
import os
import sys
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

url = os.environ['TEST_DATABASE_URL']
assert make_url(url).database.endswith('_test'), 'Disposable test database required'
engine = create_engine(url, connect_args={'connect_timeout': 5})
with engine.begin() as connection:
    revision = connection.execute(text('SELECT version_num FROM alembic_version')).scalar_one()
    if sys.argv[1] == 'seed':
        assert revision == '0003'
        assert connection.execute(text('SELECT count(*) FROM users')).scalar_one() == 0
        for email in ('backfill-good@example.test', 'backfill-invalidated@example.test'):
            user_id = connection.execute(text('INSERT INTO users (email) VALUES (:email) RETURNING id'), {'email': email}).scalar_one()
            connection.execute(text("INSERT INTO user_roles (user_id, role_id) SELECT :id, id FROM roles WHERE name='CUSTOMER'"), {'id': user_id})
            if email == 'backfill-good@example.test':
                connection.execute(text("INSERT INTO audit_logs (actor_id,action,entity_type,entity_id) VALUES (:id,'CUSTOMER_LOGIN','authentication',:id)"), {'id': user_id})
            else:
                connection.execute(text("""INSERT INTO otp_verifications (email,code_hash,expires_at,resend_after,consumed_at)
                    VALUES (:email,'invalidation-test',now()+interval '5 minutes',now()+interval '60 seconds',now())"""), {'email': email})
    elif sys.argv[1] == 'verify-cleanup':
        assert revision == '0004'
        rows = dict(connection.execute(text('SELECT email,email_verified_at FROM users')).all())
        assert rows['backfill-good@example.test'] is not None
        assert rows['backfill-invalidated@example.test'] is None
        connection.execute(text('TRUNCATE users,otp_verifications,auth_rate_limits CASCADE'))
        print('Successful-login backfill and OTP-invalidation exclusion passed; test data removed.')
    else:
        raise ValueError('Use seed or verify-cleanup')
engine.dispose()
