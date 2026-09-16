#!/usr/bin/env bash
set -euo pipefail

AWS=(aws --endpoint-url http://localhost:4566 --region eu-west-2)
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-2

"${AWS[@]}" s3api head-bucket --bucket integration-data >/dev/null 2>&1 || \
  "${AWS[@]}" s3api create-bucket --bucket integration-data \
    --create-bucket-configuration LocationConstraint=eu-west-2 >/dev/null

for queue in integration-processing integration-datalake; do
  "${AWS[@]}" sqs create-queue --queue-name "$queue" >/dev/null
done

"${AWS[@]}" secretsmanager create-secret \
  --name integration-meraki \
  --secret-string '{"api_key":"integration-api-key","webhook_secret":"integration-webhook-secret"}' \
  >/dev/null 2>&1 || \
"${AWS[@]}" secretsmanager put-secret-value \
  --secret-id integration-meraki \
  --secret-string '{"api_key":"integration-api-key","webhook_secret":"integration-webhook-secret"}' >/dev/null

"${AWS[@]}" secretsmanager create-secret \
  --name integration-rds \
  --secret-string '{"username":"platform_admin","password":"integration-password"}' \
  >/dev/null 2>&1 || \
"${AWS[@]}" secretsmanager put-secret-value \
  --secret-id integration-rds \
  --secret-string '{"username":"platform_admin","password":"integration-password"}' >/dev/null

PROCESSING_QUEUE_URL=$("${AWS[@]}" sqs get-queue-url --queue-name integration-processing --query QueueUrl --output text)
DATALAKE_QUEUE_URL=$("${AWS[@]}" sqs get-queue-url --queue-name integration-datalake --query QueueUrl --output text)

cat > .integration.env <<ENV
PROCESSING_QUEUE_URL=${PROCESSING_QUEUE_URL/localhost/localstack}
DATALAKE_QUEUE_URL=${DATALAKE_QUEUE_URL/localhost/localstack}
ENV

cat .integration.env
