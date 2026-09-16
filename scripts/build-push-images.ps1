param(
  [Parameter(Mandatory=$true)][ValidateSet("dev","uat","prod")][string]$Environment,
  [string]$Tag = "local",
  [string]$ProjectName = "occupancy-platform",
  [string]$AwsRegion = "eu-west-2"
)
$ErrorActionPreference = "Stop"
$AccountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "Unable to determine AWS account" }
$Registry = "$AccountId.dkr.ecr.$AwsRegion.amazonaws.com"
aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }
foreach ($Service in @("inbound","outbound","processor","management")) {
  $Repo = "$ProjectName-$Environment-$Service"
  $Image = "$Registry/${Repo}:$Tag"
  aws ecr describe-repositories --repository-names $Repo | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ECR repository not found: $Repo" }
  docker build -f "services/$Service/Dockerfile" -t $Image .
  if ($LASTEXITCODE -ne 0) { throw "Docker build failed: $Service" }
  docker push $Image
  if ($LASTEXITCODE -ne 0) { throw "Docker push failed: $Service" }
  Write-Host "$Service=$Image"
}
