FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/processor/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/processor/requirements.txt /app/services/processor/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/processor/requirements.txt
COPY services/processor/src /app/services/processor/src

USER 65532:65532
CMD ["python", "-m", "processor_service.worker"]
