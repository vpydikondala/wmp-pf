# Inbound service

FastAPI service exposed through CloudFront -> WAF -> VPC Origin -> internal ALB.

`POST /api/v1/meraki/webhook` validates the optional Meraki webhook secret, stores the raw JSON in S3 and publishes an S3 pointer to the processing SQS queue. `GET /health` is used by the ALB target group.

Required runtime variables: `DATA_BUCKET`, `PROCESSING_QUEUE_URL`. When webhook authentication is enabled, also set `MERAKI_SECRET_ARN`; the secret JSON must contain `webhook_secret`.
