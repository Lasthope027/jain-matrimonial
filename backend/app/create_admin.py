"""Run python -m app.create_admin --email EMAIL. Password is prompted, never an argument."""
import argparse
from getpass import getpass
from sqlalchemy import insert, select
from app.auth import EmailInput, lock, record, secret
from app.db import get_engine
from app import models as m
from app.security import hash_password, keyed_hash


def create_administrator(email: str, password: str):
    email = EmailInput(email=email).email
    if not 12 <= len(password) <= 128:
        raise ValueError('Administrator passwords must contain 12 to 128 characters')
    encoded = hash_password(password)
    with get_engine().begin() as connection:
        lock(connection, keyed_hash(secret(), 'otp:' + email))
        if connection.execute(select(m.users.c.id).where(m.users.c.email == email)).first():
            raise ValueError('An account already exists for this email. No account was changed.')
        role_id = connection.execute(select(m.roles.c.id).where(m.roles.c.name == 'ADMINISTRATOR')).scalar_one()
        user_id = connection.execute(insert(m.users).values(email=email, password_hash=encoded).returning(m.users.c.id)).scalar_one()
        connection.execute(insert(m.user_roles).values(user_id=user_id, role_id=role_id))
        record(connection, 'ADMINISTRATOR_PROVISIONED', user_id, user_id)


def main():
    parser = argparse.ArgumentParser(description='Provision an administrator locally; there is no public registration endpoint.')
    parser.add_argument('--email', required=True)
    args = parser.parse_args()
    password = getpass('New administrator password (12+ characters): ')
    if password != getpass('Confirm password: '):
        raise SystemExit('Passwords do not match')
    try:
        create_administrator(args.email, password)
    except ValueError as exc:
        raise SystemExit(str(exc)) from None
    print('Administrator created. Sign in through the administrator application.')


if __name__ == '__main__':
    main()
