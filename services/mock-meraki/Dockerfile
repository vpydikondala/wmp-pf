FROM python:3.12-slim

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*
    
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app/src
WORKDIR /app
COPY services/mock-meraki/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY services/mock-meraki/src /app/src
EXPOSE 8081
CMD ["uvicorn", "mock_meraki.app:app", "--host", "0.0.0.0", "--port", "8081", "--no-access-log"]
