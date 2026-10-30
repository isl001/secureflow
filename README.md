# SecureFlow

[![CI](https://github.com/isl001/secureflow/actions/workflows/ci.yml/badge.svg)](https://github.com/isl001/secureflow/actions/workflows/ci.yml)
[![Publish](https://github.com/isl001/secureflow/actions/workflows/publish.yml/badge.svg)](https://github.com/isl001/secureflow/actions/workflows/publish.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=isl001_secureflow&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=isl001_secureflow)

End-to-end **DevSecOps pipeline** that takes a containerised FastAPI + PostgreSQL
application from a Git commit, through automated security checks, to a running
workload on Kubernetes.

## Pipeline (current)

```
Developer ──► pre-commit (Gitleaks) ──► Pull Request ──► CI (4 required checks) ──► merge to main ──► Publish
                                                          │                                         │
                                                          ├─ build        (deps + syntax + docker)  └─ multi-arch image
                                                          ├─ secret-scan  (Gitleaks, full history)     (amd64 + arm64)
                                                          ├─ sast         (SonarCloud Quality Gate)    ──► GHCR
                                                          └─ sca          (pip-audit, known CVEs)
```

`main` is protected: no direct pushes, and a PR can only merge when **all four checks pass**.

| Workflow | Trigger | Job | What it does |
|---|---|---|---|
| `ci.yml` | pull request → `main` | `build` | Installs dependencies, compiles the app, builds the Docker image |
| | | `secret-scan` | Gitleaks scans the **entire Git history** (`fetch-depth: 0`, redacted output) |
| | | `sast` | SonarQube Cloud analysis; waits for the **Quality Gate** and fails the job if it fails |
| | | `sca` | `pip-audit` checks `requirements.txt` against known vulnerabilities (OSV / PyPI advisories); `--strict` fails closed |
| `publish.yml` | push → `main` | `publish` | Builds a multi-arch image and pushes it to GHCR tagged with the commit SHA and `latest` |

## Security controls

| Layer | Control | Status |
|---|---|---|
| Developer machine | Gitleaks pre-commit hook (blocks committed secrets) | ✅ |
| GitHub | Secret scanning + push protection | ✅ |
| GitHub | Dependabot alerts + security updates | ✅ |
| CI | Gitleaks scan of full history as a required check | ✅ |
| CI | SAST with SonarQube Cloud; Quality Gate is a required check ("Clean as You Code": judges new code) | ✅ |
| CI | SAST gate verified with a negative test (insecure code → merge **BLOCKED**) | ✅ |
| CI | SCA with `pip-audit` as a required check; verified with a negative test (vulnerable `idna` → merge **BLOCKED**) | ✅ |
| Supply chain | Third-party GitHub Actions pinned to full commit SHAs (immutable) | ✅ |
| Supply chain | `GITHUB_TOKEN` with least-privilege `permissions` (`contents: read`, `packages: write`) | ✅ |
| App | No default credentials: the app fails fast if `DATABASE_URL` is missing | ✅ |
| Config | Secrets kept out of Git: `.env` (git-ignored) + `.env.example`; Compose uses `${VAR:?}` | ✅ |
| Container | Slim base image, non-root user (UID 10001) | ✅ |
| Dependencies | Dependabot version updates (weekly) for GitHub Actions, pip and Docker; SHA pins are kept and bumped automatically | ✅ |
| Dependencies | Dependabot PRs get their own `SONAR_TOKEN` (Dependabot secrets store, separate token), so the SAST gate also runs on bot PRs | ✅ |
| Dependencies | Snyk (dependency tree, reachability) | ⏳ |
| Container | Image vulnerability scanning (Trivy) | ⏳ |
| Supply chain | SBOM (CycloneDX) + image signing | ⏳ |
| Runtime | DAST (OWASP ZAP) | ⏳ |

### Triage decisions (SonarCloud findings)

| Finding | Decision | Reason |
|---|---|---|
| Hard-coded PostgreSQL password (`app/db.py`, `compose.yaml`) | **Fixed** | Moved to environment / `.env`; fail fast when missing |
| Actions referenced by mutable tags (`@v3`) | **Fixed** | Pinned to commit SHAs; tags can be force-moved (cf. tj-actions/changed-files, 2025) |
| Path traversal in `scripts/policy_check.py` | **False positive** | CLI run by developers/CI on repo files; caller already has the same permissions, so no trust boundary is crossed. Re-evaluate if ever exposed via an API |
| Unpinned / source installs in `pip install` | **Open** | Planned with the SCA stage (hash-locked dependencies) |

## Quick start (local)

Requirements: Docker with Compose v2.

```bash
git clone https://github.com/isl001/secureflow.git
cd secureflow

# 1. Create your local secrets file (never committed)
cp .env.example .env
sed -i.bak "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env && rm .env.bak
chmod 600 .env

# 2. Run the stack
docker compose up -d --build

# 3. Check it
curl http://127.0.0.1:8000/health      # {"status":"ok"}
```

> **Note:** `POSTGRES_PASSWORD` is only applied when the database volume is first created.
> If you change it later, rotate it inside the database (`ALTER USER ... PASSWORD ...`)
> or recreate the volume (`docker compose down -v`, which **deletes the data**).

### API

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness check |
| `GET` | `/tasks` | List tasks |
| `POST` | `/tasks` | Create a task |
| `DELETE` | `/tasks/{task_id}` | Delete a task |

Interactive docs: http://127.0.0.1:8000/docs

## Roadmap

- [x] Repo + secret scanning (pre-commit, push protection)
- [x] FastAPI app + PostgreSQL with Docker Compose (healthcheck)
- [x] Non-root Dockerfile, multi-arch image
- [x] CI with GitHub Actions (build, secret-scan) as required checks
- [x] CD: publish multi-arch image to GHCR
- [x] SAST with SonarQube Cloud + Quality Gate as a required check
- [x] Supply chain: actions pinned to SHAs; secrets moved to `.env`
- [x] SCA: `pip-audit` as a required CI gate
- [x] Dependabot version updates (actions, pip, docker)
- [ ] SCA: Snyk + scan `scripts/requirements.txt`
- [ ] Container scanning with Trivy
- [ ] SBOM + image signing (Cosign)
- [ ] DAST with OWASP ZAP
- [ ] Kubernetes + ArgoCD (GitOps)
- [ ] Terraform (AWS) + Ansible
- [ ] Prometheus + Grafana

## Tech

GitHub Actions · Docker · GHCR · Gitleaks · SonarQube Cloud · pip-audit · Python · FastAPI · PostgreSQL ·
*(planned)* Trivy · Snyk · OWASP ZAP · Kubernetes · ArgoCD · Terraform · Ansible · AWS · Prometheus · Grafana
