# Workflow location

The requested canonical copies are under:

`legacy/.github/workflows/`

GitHub Actions itself only discovers workflows under the repository root:

`.github/workflows/`

Before pushing this repository to GitHub, copy the Phase-2 workflow YAML files to the root
`.github/workflows/` directory. Keep the canonical legacy-folder copies if desired for your
internal layout/documentation, but the root copies are the executable workflows.

Example PowerShell:

```powershell
New-Item -ItemType Directory -Force .github\workflows | Out-Null
Copy-Item legacy\.github\workflows\phase2-*.yml .github\workflows\
```

This does not alter the path filters: they still target `phase2/infra-deploy/**` and
`phase2/app-deploy/**`.
