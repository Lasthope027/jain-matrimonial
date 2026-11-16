import hashlib
import os
from pathlib import Path
import tempfile
from typing import Literal
from uuid import UUID, uuid4
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool
from PIL import Image
from pypdf import PdfReader
from sqlalchemy import select, insert, update, func
from app import models as m
from app.auth import rate_limit, now
from app.config import get_settings
from app.db import get_engine
from app.profiles import User, access, expected, editable, changed, audit
from app.workflow import lock_workflow

router = APIRouter(prefix='/api/v1', tags=['private documents'])
MAX_SIZE = 10 * 1024 * 1024
TYPES = {'.pdf': 'application/pdf', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png'}


def root_directory():
    root = Path(get_settings().storage_path).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def metadata(row):
    return {key: row[key] for key in ('id', 'profile_id', 'original_name', 'media_type', 'size_bytes', 'kind', 'created_at')}


def validate_content(path, media_type):
    try:
        if media_type == 'application/pdf':
            with path.open('rb') as stream:
                if not stream.read(5) == b'%PDF-':
                    raise ValueError()
                stream.seek(0)
                reader = PdfReader(stream, strict=True)
                if reader.is_encrypted or not 1 <= len(reader.pages) <= 500:
                    raise ValueError()
        else:
            with Image.open(path) as image:
                if image.format != ('PNG' if media_type == 'image/png' else 'JPEG'):
                    raise ValueError()
                if image.width * image.height > 20_000_000:
                    raise ValueError()
                image.verify()
            with Image.open(path) as image:
                image.load()  # Reject truncated image payloads, not just invalid headers.
    except Exception:
        raise HTTPException(415, 'Upload a valid PDF, JPEG or PNG. PDFs must be unencrypted with 1–500 pages; images at most 20 megapixels.') from None


def preflight(profile_id, version, user):
    rate_limit('document-upload', user['id'], 120 if user['role'] == 'ADMINISTRATOR' else 30, 3600)
    with get_engine().connect() as connection:
        profile = access(connection, profile_id, user)
        expected(profile, version)
        editable(profile, user)


def commit_upload(profile_id, version, user, temporary, destination, filename, media_type, size, digest, kind):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        profile = access(connection, profile_id, user, locked=True)
        expected(profile, version)
        editable(profile, user)
        count = connection.execute(select(func.count()).select_from(m.documents).where(
            m.documents.c.profile_id == profile_id, m.documents.c.deleted_at.is_(None))).scalar_one()
        if count >= 20:
            raise HTTPException(409, 'A profile can have at most 20 active documents. Remove an existing document first.')
        temporary.replace(destination)
        row = connection.execute(insert(m.documents).values(profile_id=profile_id, uploaded_by=UUID(user['id']),
            storage_key=destination.name, original_name=filename, media_type=media_type,
            size_bytes=size, sha256=digest, kind=kind).returning(m.documents)).mappings().one()
        changed(connection, profile, user, 'DOCUMENT_UPLOADED')
        return {'document': metadata(row), 'profile_version': profile['version']+1}


@router.post('/profiles/{profile_id}/documents', status_code=201, openapi_extra={
    'requestBody': {'required': True, 'content': {
        media: {'schema': {'type': 'string', 'format': 'binary'}}
        for media in ('application/pdf', 'image/jpeg', 'image/png')}}})
async def upload(profile_id: UUID, request: Request, user: User,
                 version: int = Query(ge=1), filename: str = Query(min_length=1, max_length=255),
                 kind: Literal['PHOTO', 'BIODATA'] = Query()):
    if any(c in filename for c in ('/', '\\')) or any(ord(c) < 32 or ord(c) == 127 for c in filename):
        raise HTTPException(422, 'Use a filename without paths or control characters')
    suffix = Path(filename).suffix.lower()
    media_type = request.headers.get('content-type', '').split(';', 1)[0].strip().lower()
    if suffix not in TYPES or media_type != TYPES[suffix] or (kind == 'PHOTO' and suffix == '.pdf'):
        raise HTTPException(415, 'Filename, content type and document kind must match PDF/JPEG/PNG content')
    try:
        if int(request.headers.get('content-length', '0')) > MAX_SIZE:
            raise HTTPException(413, 'Maximum file size is 10 MiB')
    except ValueError:
        raise HTTPException(400, 'Invalid content length') from None
    await run_in_threadpool(preflight, profile_id, version, user)
    root = await run_in_threadpool(root_directory)
    descriptor, name = tempfile.mkstemp(dir=root, suffix='.part')
    temporary, destination = Path(name), root / (uuid4().hex + suffix)
    committed = False
    try:
        size = 0
        digest = hashlib.sha256()
        with os.fdopen(descriptor, 'wb') as output:
            async for chunk in request.stream():
                size += len(chunk)
                if size > MAX_SIZE:
                    raise HTTPException(413, 'Maximum file size is 10 MiB')
                digest.update(chunk)
                await run_in_threadpool(output.write, chunk)
        if size == 0:
            raise HTTPException(415, 'The file is empty')
        await run_in_threadpool(validate_content, temporary, media_type)
        result = await run_in_threadpool(commit_upload, profile_id, version, user, temporary, destination,
            filename, media_type, size, digest.hexdigest(), kind)
        committed = True
        return result
    except OSError:
        raise HTTPException(503, 'Private file storage is unavailable') from None
    finally:
        temporary.unlink(missing_ok=True)
        if not committed:
            destination.unlink(missing_ok=True)


@router.get('/profiles/{profile_id}/documents')
def list_documents(profile_id: UUID, user: User):
    with get_engine().connect() as connection:
        access(connection, profile_id, user)
        return {'items': [metadata(row) for row in connection.execute(select(m.documents).where(
            m.documents.c.profile_id == profile_id, m.documents.c.deleted_at.is_(None))
            .order_by(m.documents.c.created_at)).mappings()]}


def document(connection, document_id, user, *, locked=False):
    row = connection.execute(select(m.documents).where(m.documents.c.id == document_id, m.documents.c.deleted_at.is_(None))).mappings().first()
    if not row:
        raise HTTPException(404, 'Document not found')
    profile = access(connection, row['profile_id'], user, locked=locked)
    return row, profile


def file_path(key):
    root = root_directory()
    path = (root / key).resolve()
    if not path.is_relative_to(root) or path.parent != root:
        raise HTTPException(404, 'Document not found')
    return path


@router.get('/documents/{document_id}/download')
def download(document_id: UUID, user: User):
    with get_engine().begin() as connection:
        row, profile = document(connection, document_id, user)
        path = file_path(row['storage_key'])
        if not path.is_file():
            raise HTTPException(404, 'Document not found')
        audit(connection, user, 'DOCUMENT_DOWNLOADED', profile['id'], {'document_id': str(document_id)})
        return FileResponse(path, media_type=row['media_type'], filename=row['original_name'],
            content_disposition_type='attachment', headers={'Content-Security-Policy': "sandbox; default-src 'none'"})


@router.delete('/documents/{document_id}')
def remove_document(document_id: UUID, user: User, version: int = Query(ge=1)):
    with get_engine().begin() as connection:
        lock_workflow(connection)
        row, profile = document(connection, document_id, user, locked=True)
        expected(profile, version)
        editable(profile, user)
        # Recheck after taking the profile lock to serialise concurrent removals.
        row, _ = document(connection, document_id, user)
        connection.execute(update(m.documents).where(m.documents.c.id == document_id).values(deleted_at=now()))
        changed(connection, profile, user, 'DOCUMENT_REMOVED')
        path = file_path(row['storage_key'])
    try:
        path.unlink(missing_ok=True)
    except OSError:
        # The record is already inaccessible. An operator may remove orphaned bytes later.
        pass
    return {'profile_version': profile['version']+1}
