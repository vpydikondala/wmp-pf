$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force ".github/workflows" | Out-Null
Copy-Item "legacy/.github/workflows/phase2-*.yml" ".github/workflows/" -Force
Write-Host "Installed Phase-2 GitHub Actions workflows into .github/workflows/"
