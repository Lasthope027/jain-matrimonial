FROM python:3.12-slim
WORKDIR /project
COPY backend/requirements.lock.txt backend/requirements.lock.txt
RUN pip install --no-cache-dir -r backend/requirements.lock.txt
COPY backend backend
COPY database database
COPY alembic.ini .
ENV PYTHONPATH=/project/backend
RUN useradd --create-home app && mkdir -p /project/storage/private && chown -R app:app /project
USER app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
