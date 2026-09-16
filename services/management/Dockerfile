FROM python:3.12-slim

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
    
WORKDIR /app
COPY services/management/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY services/management/src /app/src
COPY services/management/migrations /app/migrations
ENV PYTHONPATH=/app/src
ENV MANAGEMENT_MIGRATIONS_PATH=/app/migrations
EXPOSE 8090
CMD ["uvicorn", "management_service.app:app", "--host", "0.0.0.0", "--port", "8090"]
