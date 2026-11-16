from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError
from sqlalchemy.schema import CreateTable
from sqlalchemy.dialects import postgresql
from app.main import app
from app.models import metadata


def test_health_and_no_personal_data_routes():
    client = TestClient(app)
    assert client.get('/api/v1/health').json()['phase'] == 5
    assert client.get('/api/v1/profiles').status_code == 401


def test_readiness_fails_closed_without_database():
    with patch('app.main.get_engine', side_effect=OperationalError('connect', {}, Exception('private password'))):
        response = TestClient(app).get('/api/v1/ready')
    assert response.status_code == 503
    assert 'password' not in response.text


def test_schema_compiles_for_postgres():
    assert len(metadata.tables) == 17
    for table in metadata.sorted_tables:
        assert 'id' in table.c and 'created_at' in table.c and 'updated_at' in table.c
        assert str(CreateTable(table).compile(dialect=postgresql.dialect()))


def test_migration_snapshot_matches_models():
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location('initial', Path(__file__).parents[2] / 'database/migrations/versions/0001_foundation.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    frozen = module.snapshot()
    for name, table in frozen.tables.items():
        # Later migrations can add columns while retaining the original structure.
        current = metadata.tables[name]
        for column in table.columns:
            assert column.name in current.c
            assert column.nullable == current.c[column.name].nullable
            assert str(column.type.compile(dialect=postgresql.dialect())) == str(current.c[column.name].type.compile(dialect=postgresql.dialect()))
