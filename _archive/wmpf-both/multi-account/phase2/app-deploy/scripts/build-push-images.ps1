\
param([Parameter(Mandatory=$true)][string]$Environment,
      [Parameter(Mandatory=$true)][string]$Tag)
$ErrorActionPreference = "Stop"
$region = if ($env:AWS_REGION) { $env:AWS_REGION } else { "eu-west-2" }
$account = aws sts get-caller-identity --query Account --output text
$registry = "$account.dkr.ecr.$region.amazonaws.com"
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
foreach ($svc in @("inbound","processor","management","dashboard_sync")) {
  $repo = "occupancy-platform-$Environment-$svc"
  docker build -t "${repo}:$Tag" "services/$svc"
  docker tag "${repo}:$Tag" "${registry}/${repo}:$Tag"
  docker push "${registry}/${repo}:$Tag"
}
