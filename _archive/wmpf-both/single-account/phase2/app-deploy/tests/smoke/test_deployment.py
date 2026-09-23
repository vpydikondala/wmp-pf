import os
import boto3
import requests

ENV = os.environ.get("ENVIRONMENT", "dev")
REGION = os.environ.get("AWS_REGION", "eu-west-2")
BASE_URL = os.environ.get("BASE_URL", "").rstrip("/")

def test_ecs_services_are_stable():
    ecs = boto3.client("ecs", region_name=REGION)
    cluster = f"occupancy-platform-{ENV}-ecs"
    names = [f"occupancy-platform-{ENV}-{x}" for x in ("inbound", "processor", "management")]
    response = ecs.describe_services(cluster=cluster, services=names)
    assert len(response["services"]) == 3
    for svc in response["services"]:
        assert svc["runningCount"] >= svc["desiredCount"]

def test_public_health_endpoint():
    if not BASE_URL:
        return
    response = requests.get(f"{BASE_URL}/health", timeout=15)
    assert response.status_code == 200
