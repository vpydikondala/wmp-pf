FROM python:3.12-slim

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/outbound/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/outbound/requirements.txt /app/services/outbound/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/outbound/requirements.txt
COPY services/outbound/src /app/services/outbound/src

USER 65532:65532
CMD ["python", "-m", "outbound_service.worker"]
