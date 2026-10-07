# SecureFlow

End-to-end **DevSecOps pipeline** that takes a containerised FastAPI + PostgreSQL
application from a Git commit, through automated security checks, to a running
workload on Kubernetes.

## Security controls (so far)

| Layer | Control | Status |
|---|---|---|
| Developer machine | Gitleaks pre-commit hook (blocks committed secrets) | ✅ |
| GitHub | Secret scanning + push protection | ✅ |
| GitHub | Dependabot alerts + security updates | ✅ |

## Roadmap

- [x] Repo + secret scanning
- [ ] FastAPI + PostgreSQL app
- [ ] Docker (non-root, Trivy scan)
- [ ] Jenkins pipeline (Gitleaks, SonarQube, Trivy, OWASP ZAP)
- [ ] Terraform (AWS) + Ansible
- [ ] Kubernetes + ArgoCD (GitOps)
- [ ] Prometheus + Grafana

## Tech

Jenkins · Docker · Kubernetes · ArgoCD · Terraform · Ansible · AWS · Gitleaks ·
SonarQube · Trivy · OWASP ZAP · Prometheus · Grafana · Python · FastAPI · PostgreSQL
