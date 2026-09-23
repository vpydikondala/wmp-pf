FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/dashboard_sync/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/dashboard_sync/requirements.txt /app/services/dashboard_sync/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/dashboard_sync/requirements.txt
COPY services/dashboard_sync/src /app/services/dashboard_sync/src

USER 65532:65532
CMD ["python", "-m", "dashboard_sync_service.worker"]
