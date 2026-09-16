FROM python:3.12-slim

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/inbound/src

WORKDIR /app
COPY services/common /app/services/common
COPY services/inbound/requirements.txt /app/services/inbound/requirements.txt
RUN pip install --no-cache-dir /app/services/common \
    && pip install --no-cache-dir -r /app/services/inbound/requirements.txt
COPY services/inbound/src /app/services/inbound/src

USER 65532:65532
EXPOSE 8080
CMD ["uvicorn", "inbound_service.app:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
