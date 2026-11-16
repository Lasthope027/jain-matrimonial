import io
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from uuid import uuid4
import pytest
from PIL import Image
from pypdf import PdfWriter
from sqlalchemy import select, update
from fastapi.testclient import TestClient
from app import profiles, documents, models as m
from app.main import app
from app.create_admin import create_administrator
from test_auth import database, register, headers


@pytest.fixture
def context(database, monkeypatch, tmp_path):
    engine, settings, client = database
    settings.storage_path = str(tmp_path)
    monkeypatch.setattr(profiles, 'get_engine', lambda: engine)
    monkeypatch.setattr(documents, 'get_engine', lambda: engine)
    monkeypatch.setattr(documents, 'get_settings', lambda: settings)
    a, _ = register(client, 'parent-a@example.test')
    b, _ = register(client, 'parent-b@example.test')
    create_administrator('admin@example.test', 'long-test-password')
    admin = client.post('/api/v1/auth/admin/login', json={'email': 'admin@example.test', 'password': 'long-test-password'}).json()
    return engine, client, headers(a), headers(b), headers(admin), tmp_path


def payload(**overrides):
    body = dict(full_name='Asha Jain', gender='FEMALE', date_of_birth='1996-05-12',
        height_cm=165, marital_status='NEVER_MARRIED', community='Shwetambar', sub_community='Sthanakvasi',
        current_location='Pune', education={'qualification': 'M.Com', 'profession': 'Accountant', 'annual_income': '600000.00'},
        family={'father_name': 'Parent', 'siblings': 1}, preferences={'age_min': 27, 'age_max': 35, 'locations': ['Pune','Mumbai']})
    body.update(overrides)
    return body


def create(client, authorization, **overrides):
    response = client.post('/api/v1/profiles', headers=authorization, json=payload(**overrides))
    assert response.status_code == 201, response.text
    return response.json()


def image_bytes(kind='PNG'):
    stream = io.BytesIO()
    Image.new('RGB', (12, 12), 'white').save(stream, kind)
    return stream.getvalue()


def upload(client, authorization, profile, content=None, filename='photo.png', kind='PHOTO', mime='image/png', **kwargs):
    return client.post(f"/api/v1/profiles/{profile['id']}/documents",
        headers={**authorization, 'Content-Type': mime},
        params={'version': profile['version'], 'filename': filename, 'kind': kind},
        content=image_bytes() if content is None else content, **kwargs)


def test_creation_multi_profile_and_private_access(context):
    engine, client, a, b, admin, _ = context
    p = create(client, a)
    create(client, a, full_name='Second Child')
    assert p['status'] == 'PENDING_VERIFICATION' and p['version'] == 1
    assert p['education']['qualification'] == 'M.Com' and p['preferences']['locations'] == ['Pune','Mumbai']
    assert len(client.get('/api/v1/profiles', headers=a).json()['items']) == 2
    assert client.get('/api/v1/profiles', headers=b).json()['items'] == []
    assert client.get(f"/api/v1/profiles/{p['id']}", headers=b).status_code == 404
    assert client.get('/api/v1/admin/profiles', headers=a).status_code == 403
    assert len(client.get('/api/v1/admin/profiles', headers=admin).json()['items']) == 2
    assert client.get(f"/api/v1/profiles/{p['id']}", headers=admin).status_code == 200
    with engine.connect() as conn:
        assert conn.execute(select(m.notifications.c.event).where(m.notifications.c.event == 'PROFILE_SUBMITTED')).first()


def test_admin_manual_profile_later_association_and_reassignment(context):
    _, client, a, b, admin, _ = context
    p = client.post('/api/v1/admin/profiles', headers=admin, json=payload(status='APPROVED')).json()
    assert p['account_email'] is None and p['status'] == 'APPROVED'
    assert client.get('/api/v1/profiles', headers=a).json()['items'] == []
    response = client.put(f"/api/v1/admin/profiles/{p['id']}/account", headers=admin,
        json={'version': p['version'], 'email': 'parent-a@example.test'})
    assert response.status_code == 200
    p = response.json()
    doc = upload(client, admin, p).json()['document']
    p = client.get(f"/api/v1/profiles/{p['id']}", headers=admin).json()
    p = client.put(f"/api/v1/admin/profiles/{p['id']}/account", headers=admin,
        json={'version': p['version'], 'email': 'parent-b@example.test'}).json()
    assert client.get(f"/api/v1/profiles/{p['id']}", headers=a).status_code == 404
    assert client.get(f"/api/v1/documents/{doc['id']}/download", headers=a).status_code == 404
    assert client.get(f"/api/v1/documents/{doc['id']}/download", headers=b).status_code == 200
    assert client.put(f"/api/v1/admin/profiles/{p['id']}/account", headers=admin,
        json={'version': p['version'], 'email': 'admin@example.test'}).status_code == 422


def test_verification_edit_reverification_and_stale_writes(context):
    _, client, a, b, admin, _ = context
    p = create(client, a)
    url = f"/api/v1/admin/profiles/{p['id']}/verification"
    assert client.put(url, headers=a, json={'version': 1, 'status': 'APPROVED'}).status_code == 403
    p = client.put(url, headers=admin, json={'version': 1, 'status': 'APPROVED'}).json()
    assert p['verified_by'] and p['status'] == 'APPROVED'
    assert client.put(f"/api/v1/profiles/{p['id']}", headers=b, json=payload(version=p['version'])).status_code == 404
    edited = client.put(f"/api/v1/profiles/{p['id']}", headers=a, json=payload(version=p['version'], full_name='Updated Name'))
    assert edited.status_code == 200
    assert edited.json()['status'] == 'PENDING_VERIFICATION' and edited.json()['verified_by'] is None
    assert client.put(f"/api/v1/profiles/{p['id']}", headers=a, json=payload(version=p['version'])).status_code == 409
    assert client.put(url, headers=admin, json={'version': edited.json()['version'], 'status': 'REJECTED'}).status_code == 422


@pytest.mark.parametrize('values', [
    {'status':'APPROVED'}, {'account_email':'parent-b@example.test'}, {'created_by':str(uuid4())},
    {'date_of_birth':date.today().isoformat()}, {'height_cm':0},
    {'preferences':{'age_min':40,'age_max':20}}, {'education':{'annual_income':-1}},
    {'gender':'invalid'}, {'full_name':'   '}, {'family':{'siblings':-1}}])
def test_validation_rejects_spoofed_ownership_and_invalid_biodata(context, values):
    _, client, a, _, _, _ = context
    assert client.post('/api/v1/profiles', headers=a, json=payload(**values)).status_code == 422


def test_document_privacy_download_and_removal(context):
    engine, client, a, b, admin, root = context
    p = create(client, a)
    response = upload(client, a, p)
    assert response.status_code == 201, response.text
    doc = response.json()['document']
    assert 'storage_key' not in doc and 'uploaded_by' not in doc
    assert client.get(f"/api/v1/profiles/{p['id']}/documents", headers=b).status_code == 404
    url = f"/api/v1/documents/{doc['id']}/download"
    assert client.get(url).status_code == 401
    assert client.get(url, headers=b).status_code == 404
    result = client.get(url, headers=a)
    assert result.status_code == 200 and result.content == image_bytes()
    assert 'attachment' in result.headers['content-disposition']
    assert result.headers['cache-control'] == 'no-store'
    assert client.get('/storage/' + doc['id']).status_code == 404
    assert client.delete(f"/api/v1/documents/{doc['id']}?version=2", headers=b).status_code == 404
    assert client.delete(f"/api/v1/documents/{doc['id']}?version=2", headers=a).status_code == 200
    assert client.get(url, headers=admin).status_code == 404
    assert not list(root.iterdir())
    with engine.connect() as conn:
        assert conn.execute(select(m.documents.c.deleted_at)).scalar_one() is not None


@pytest.mark.parametrize('content,filename,kind,mime', [
    (b'fake', 'photo.png','PHOTO','image/png'), (b'%PDF-fake','bio.pdf','BIODATA','application/pdf'),
    (b'', 'bio.pdf','BIODATA','application/pdf'), (b'fake','photo.exe','PHOTO','image/png'),
    (b'fake','../photo.png','PHOTO','image/png'), (b'fake','photo.png','PHOTO','application/pdf'),
    (b'fake','bio.pdf','PHOTO','application/pdf')])
def test_invalid_uploads_do_not_leave_files(context, content, filename, kind, mime):
    _, client, a, _, _, root = context
    p = create(client, a)
    assert upload(client, a, p, content, filename, kind, mime).status_code in (415,422)
    assert not list(root.iterdir())


def test_pdf_jpeg_and_streaming_size_limits(context):
    _, client, a, _, _, root = context
    p = create(client, a)
    buffer = io.BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=100, height=100)
    writer.write(buffer)
    result = upload(client, a, p, buffer.getvalue(), 'bio.pdf', 'BIODATA', 'application/pdf')
    assert result.status_code == 201, result.text
    p['version'] = result.json()['profile_version']
    result = upload(client, a, p, image_bytes('JPEG'), 'photo.jpeg', 'PHOTO', 'image/jpeg')
    assert result.status_code == 201
    p['version'] = result.json()['profile_version']
    huge = (b'x'*1024*1024 for _ in range(11))
    assert upload(client, a, p, huge).status_code == 413
    assert len(list(root.iterdir())) == 2


def test_upload_triggers_reverification_and_inactive_blocks_mutations(context):
    _, client, a, _, admin, _ = context
    p = create(client, a)
    url = f"/api/v1/admin/profiles/{p['id']}/verification"
    p = client.put(url, headers=admin, json={'version': p['version'], 'status': 'APPROVED'}).json()
    assert upload(client, a, p).status_code == 201
    p = client.get(f"/api/v1/profiles/{p['id']}", headers=a).json()
    assert p['status'] == 'PENDING_VERIFICATION'
    p = client.put(url, headers=admin, json={'version': p['version'], 'status': 'INACTIVE'}).json()
    assert upload(client, a, p).status_code == 409
    assert client.put(f"/api/v1/profiles/{p['id']}", headers=a, json=payload(version=p['version'])).status_code == 409


def test_concurrent_edits_have_one_winner(context):
    _, client, a, _, _, _ = context
    p = create(client, a)
    def edit(i):
        return TestClient(app).put(f"/api/v1/profiles/{p['id']}", headers=a, json=payload(version=1, full_name=f'Edit {i}')).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(edit, range(2))) == [200,409]


def test_concurrent_uploads_cleanup_the_stale_file(context):
    engine, client, a, _, _, root = context
    p = create(client, a)
    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses = list(pool.map(lambda _: upload(TestClient(app), a, p).status_code, range(2)))
    assert sorted(statuses) == [201,409]
    assert len(list(root.iterdir())) == 1
    with engine.connect() as conn:
        assert len(conn.execute(select(m.documents)).all()) == 1


def test_image_content_must_match_extension_and_mime(context):
    _, client, a, _, _, root = context
    p = create(client, a)
    assert upload(client, a, p, image_bytes(), 'photo.jpg','PHOTO','image/jpeg').status_code == 415
    assert not list(root.iterdir())


def test_download_rejects_escaped_storage_keys(context):
    engine, client, a, _, admin, _ = context
    p = create(client, a)
    doc = upload(client, a, p).json()['document']
    with engine.begin() as conn:
        conn.execute(update(m.documents).values(storage_key='../outside.png'))
    assert client.get(f"/api/v1/documents/{doc['id']}/download", headers=admin).status_code == 404
