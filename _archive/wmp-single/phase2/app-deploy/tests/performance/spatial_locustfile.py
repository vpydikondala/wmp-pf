import random
from locust import HttpUser, between, task


class SpatialPresenceUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task(8)
    def observation(self):
        self.client.post("/api/observe", json={
            "device_id": f"load-{random.randint(1,1000)}",
            "x": random.uniform(5,95),
            "y": random.uniform(5,95),
            "confidence": 0.85,
        })

    @task(2)
    def dashboard(self):
        self.client.get("/api/occupancy")
