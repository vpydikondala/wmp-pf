#!/usr/bin/env bash
set -euo pipefail
mkdir -p .github/workflows
cp legacy/.github/workflows/phase2-*.yml .github/workflows/
echo "Installed Phase-2 GitHub Actions workflows into .github/workflows/"
