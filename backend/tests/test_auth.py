import os
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from unittest.mock import Mock, patch
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError, SecretStr
from sqlalchemy import create_engine, select, update, text
from sqlalchemy.engine import make_url
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from app import auth, create_admin, models as m
from app.config import Settings
from app.main import app
from app.security import token_hash, verify_password


@pytest.fixture
def database(monkeypatch):
    url = os.getenv('TEST_DATABASE_URL')
    if not url:
        pytest.skip('Disposable PostgreSQL not configured')
    if not make_url(url).database.endswith('_test'):
        pytest.fail('Authentication tests require a disposable database ending in _test')
    engine = create_engine(url, connect_args={'connect_timeout': 5}, pool_size=8)
    settings = Settings(_env_file=None, environment='test', auth_secret='test-secret-' + 'x'*64)
    monkeypatch.setattr(auth, 'get_engine', lambda: engine)
    monkeypatch.setattr(create_admin, 'get_engine', lambda: engine)
    monkeypatch.setattr(auth, 'get_settings', lambda: settings)
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE users, otp_verifications, auth_rate_limits CASCADE'))
    yield engine, settings, TestClient(app)
    with engine.begin() as conn:
        conn.execute(text('TRUNCATE users, otp_verifications, auth_rate_limits CASCADE'))
    engine.dispose()


def register(client, email='family@example.test'):
    response = client.post('/api/v1/auth/otp/request', json={'email': email})
    assert response.status_code == 202, response.text
    code = response.json()['development_otp']
    response = client.post('/api/v1/auth/otp/verify', json={'email': email, 'code': code})
    assert response.status_code == 200, response.text
    return response.json(), code


def headers(session):
    return {'Authorization': 'Bearer ' + session['access_token']}


def test_registration_session_hashes_and_role_isolation(database):
    engine, _, client = database
    session, code = register(client, ' Family@Example.Test ')
    me = client.get('/api/v1/auth/me', headers=headers(session))
    assert me.json()['email'] == 'family@example.test'
    assert me.json()['role'] == 'CUSTOMER'
    assert client.get('/api/v1/admin/session', headers=headers(session)).status_code == 403
    assert client.get('/api/v1/customer/session', headers=headers(session)).status_code == 200
    assert client.get('/api/v1/auth/me').status_code == 401
    assert client.get('/api/v1/auth/me', headers={'Authorization': 'Bearer fake'}).status_code == 401
    assert client.post('/api/v1/auth/otp/verify', json={'email': 'family@example.test', 'code': code}).status_code == 401
    with engine.connect() as conn:
        otp = conn.execute(select(m.otp)).mappings().one()
        assert otp['code_hash'] != code and len(otp['code_hash']) == 64 and otp['consumed_at']
        assert otp['expires_at'] - otp['created_at'] <= timedelta(minutes=5, seconds=1)
        row = conn.execute(select(m.sessions)).mappings().one()
        assert row['access_hash'] == token_hash(session['access_token'])
        assert row['refresh_hash'] == token_hash(session['refresh_token'])
        assert row['access_expires_at'] - row['created_at'] <= timedelta(minutes=15, seconds=1)
        assert conn.execute(select(m.notifications.c.event)).scalar_one() == 'REGISTRATION_COMPLETED'
        assert len(conn.execute(select(m.users)).all()) == 1
    assert me.headers['cache-control'] == 'no-store'


def test_wrong_attempts_commit_and_five_is_final(database):
    engine, _, client = database
    code = client.post('/api/v1/auth/otp/request', json={'email': 'a@example.test'}).json()['development_otp']
    wrong = '000001' if code != '000001' else '000002'
    for _ in range(5):
        assert client.post('/api/v1/auth/otp/verify', json={'email': 'a@example.test', 'code': wrong}).status_code == 401
    assert client.post('/api/v1/auth/otp/verify', json={'email': 'a@example.test', 'code': code}).status_code == 401
    with engine.connect() as conn:
        assert conn.execute(select(m.otp.c.attempts)).scalar_one() == 5
        assert not conn.execute(select(m.users)).first()


def test_expiry_resend_and_old_code_invalidation(database):
    engine, _, client = database
    email = 'a@example.test'
    code = client.post('/api/v1/auth/otp/request', json={'email': email}).json()['development_otp']
    assert client.post('/api/v1/auth/otp/request', json={'email': email}).status_code == 429
    with engine.begin() as conn:
        conn.execute(update(m.otp).values(expires_at=auth.now()-timedelta(seconds=1), resend_after=auth.now()-timedelta(seconds=1)))
    assert client.post('/api/v1/auth/otp/verify', json={'email': email, 'code': code}).status_code == 401
    new = client.post('/api/v1/auth/otp/request', json={'email': email}).json()['development_otp']
    with engine.connect() as conn:
        rows = conn.execute(select(m.otp).order_by(m.otp.c.created_at)).mappings().all()
        assert rows[0]['consumed_at'] is not None
    assert client.post('/api/v1/auth/otp/verify', json={'email': email, 'code': new}).status_code == 200


def test_refresh_rotation_logout_and_expiry(database):
    engine, _, client = database
    session, _ = register(client)
    with engine.begin() as conn:
        conn.execute(update(m.sessions).values(access_expires_at=auth.now()-timedelta(seconds=1)))
    assert client.get('/api/v1/auth/me', headers=headers(session)).status_code == 401
    new = client.post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']})
    assert new.status_code == 200
    renewed = new.json()
    assert renewed['refresh_expires_at'] == session['refresh_expires_at']
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']}).status_code == 401
    assert client.get('/api/v1/auth/me', headers=headers(renewed)).status_code == 200
    assert client.post('/api/v1/auth/logout', json={'refresh_token': renewed['refresh_token']}).status_code == 204
    assert client.get('/api/v1/auth/me', headers=headers(renewed)).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': renewed['refresh_token']}).status_code == 401


def test_admin_separate_login_cannot_be_created_or_entered_by_otp(database):
    engine, _, client = database
    password = 'correct-long-admin-password'
    create_admin.create_administrator('admin@example.test', password)
    with engine.connect() as conn:
        stored = conn.execute(select(m.users.c.password_hash)).scalar_one()
        assert stored != password and verify_password(password, stored)
    assert client.post('/api/v1/auth/admin/login', json={'email': 'admin@example.test', 'password': 'wrong'}).status_code == 401
    admin = client.post('/api/v1/auth/admin/login', json={'email': 'admin@example.test', 'password': password})
    assert admin.status_code == 200
    assert client.get('/api/v1/admin/session', headers=headers(admin.json())).status_code == 200
    assert client.get('/api/v1/customer/session', headers=headers(admin.json())).status_code == 403
    code = client.post('/api/v1/auth/otp/request', json={'email': 'admin@example.test'}).json()['development_otp']
    assert client.post('/api/v1/auth/otp/verify', json={'email': 'admin@example.test', 'code': code}).status_code == 401
    customer, _ = register(client)
    assert client.post('/api/v1/auth/admin/login', json={'email': 'family@example.test', 'password': password}).status_code == 401
    with pytest.raises(ValueError):
        create_admin.create_administrator('family@example.test', password)
    assert client.post('/api/v1/auth/admin/register', json={}).status_code == 404


def test_inactive_account_cannot_use_or_refresh_sessions(database):
    engine, _, client = database
    session, _ = register(client)
    with engine.begin() as conn:
        conn.execute(update(m.users).values(active=False))
    assert client.get('/api/v1/auth/me', headers=headers(session)).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']}).status_code == 401


def test_rate_limit_persists_across_client_instances(database):
    engine, _, client = database
    for _ in range(5):
        assert client.post('/api/v1/auth/admin/login', json={'email': 'unknown@example.test', 'password': 'wrong'}).status_code == 401
    assert TestClient(app).post('/api/v1/auth/admin/login', json={'email': 'unknown@example.test', 'password': 'wrong'}).status_code == 429
    with engine.connect() as conn:
        assert conn.execute(select(m.rate_limits.c.request_count).where(m.rate_limits.c.request_count == 5)).first()


def test_concurrent_code_verification_has_one_winner(database):
    engine, _, client = database
    code = client.post('/api/v1/auth/otp/request', json={'email': 'a@example.test'}).json()['development_otp']
    def verify(_):
        return TestClient(app).post('/api/v1/auth/otp/verify', json={'email': 'a@example.test', 'code': code}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(verify, range(2))) == [200, 401]
    with engine.connect() as conn:
        assert len(conn.execute(select(m.sessions)).all()) == 1


def test_smtp_path_does_not_return_or_log_code_and_failure_invalidates(database, caplog):
    engine, settings, client = database
    settings.otp_delivery = 'smtp'
    with patch('app.auth.send_otp') as delivery:
        response = client.post('/api/v1/auth/otp/request', json={'email': 'a@example.test'})
        assert response.status_code == 202 and 'development_otp' not in response.json()
        code = delivery.call_args.args[2]
        assert code not in caplog.text
    with patch('app.auth.send_otp', side_effect=RuntimeError('DO-NOT-LOG-OTP')):
        response = client.post('/api/v1/auth/otp/request', json={'email': 'b@example.test'})
        assert response.status_code == 503 and 'DO-NOT-LOG' not in response.text + caplog.text
    with engine.connect() as conn:
        assert conn.execute(select(m.otp.c.consumed_at).where(m.otp.c.email == 'b@example.test')).scalar_one() is not None


def test_smtp_uses_tls_and_environment_credentials():
    from app.mailer import send_otp
    settings = Settings(_env_file=None, smtp_host='smtp.example.test', smtp_from='consultancy@example.test',
                        smtp_username='configured-user', smtp_password='configured-password')
    with patch('app.mailer.smtplib.SMTP') as factory:
        send_otp(settings, 'family@example.test', '123456')
        smtp = factory.return_value.__enter__.return_value
        smtp.starttls.assert_called_once()
        smtp.login.assert_called_once_with('configured-user', 'configured-password')
        smtp.send_message.assert_called_once()


def test_production_rejects_development_delivery_and_http(monkeypatch):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, environment='production', auth_secret='x'*64, otp_delivery='development')
    settings = Settings(_env_file=None, environment='production', auth_secret='x'*64,
                        otp_delivery='smtp', smtp_host='smtp.example.test', smtp_from='a@example.test')
    monkeypatch.setattr('app.main.get_settings', lambda: settings)
    client = TestClient(app)
    assert client.get('/api/v1/health').status_code == 426
    assert TestClient(app, base_url='https://testserver').get('/api/v1/health').status_code == 200


def test_validation_does_not_echo_secrets():
    response = TestClient(app).post('/api/v1/auth/admin/login', json={'email': 'invalid', 'password': 'my-private-password', 'unexpected': 'private-value'})
    assert response.status_code == 422
    assert 'my-private-password' not in response.text and 'private-value' not in response.text


def test_schema_matches_auth_migration(database):
    engine, _, _ = database
    with engine.connect() as conn:
        assert compare_metadata(MigrationContext.configure(conn), m.metadata) == []


def test_expired_refresh_token_is_rejected(database):
    engine, _, client = database
    session, _ = register(client)
    with engine.begin() as conn:
        conn.execute(update(m.sessions).values(access_expires_at=auth.now()-timedelta(days=2), refresh_expires_at=auth.now()-timedelta(days=1)))
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']}).status_code == 401


def test_concurrent_refresh_has_one_winner(database):
    _, _, client = database
    session, _ = register(client)
    def refresh(_):
        return TestClient(app).post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(refresh, range(2))) == [200, 401]


def test_ip_rate_limit_covers_different_addresses(database):
    _, _, client = database
    for i in range(20):
        assert client.post('/api/v1/auth/otp/request', json={'email': f'family{i}@example.test'}).status_code == 202
    assert client.post('/api/v1/auth/otp/request', json={'email': 'another@example.test'}).status_code == 429


def test_inactive_and_existing_customer_cannot_be_recreated(database):
    engine, _, client = database
    _, _ = register(client)
    with engine.begin() as conn:
        conn.execute(update(m.users).values(active=False))
        conn.execute(update(m.otp).values(resend_after=auth.now()-timedelta(seconds=1)))
    code = client.post('/api/v1/auth/otp/request', json={'email': 'family@example.test'}).json()['development_otp']
    assert client.post('/api/v1/auth/otp/verify', json={'email': 'family@example.test', 'code': code}).status_code == 401
    with engine.connect() as conn:
        assert len(conn.execute(select(m.users)).all()) == 1


def test_account_login_reuses_account_and_registration_notification(database):
    engine, _, client = database
    _, _ = register(client)
    with engine.begin() as conn:
        conn.execute(update(m.otp).values(resend_after=auth.now()-timedelta(seconds=1)))
    _, _ = register(client)
    with engine.connect() as conn:
        assert len(conn.execute(select(m.users)).all()) == 1
        assert len(conn.execute(select(m.notifications)).all()) == 1
        assert len(conn.execute(select(m.sessions)).all()) == 2
