#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT=${1:?environment required}
TAG=${2:-${GITHUB_SHA:-local}}
PROJECT_NAME=${PROJECT_NAME:-occupancy-platform}
AWS_REGION=${AWS_REGION:-eu-west-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for service in inbound outbound processor management; do
  repo="${PROJECT_NAME}-${ENVIRONMENT}-${service}"
  image="${REGISTRY}/${repo}:${TAG}"
  aws ecr describe-repositories --repository-names "$repo" >/dev/null
  docker build -f "services/${service}/Dockerfile" -t "$image" .
  docker push "$image"
  echo "$service=$image"
done
