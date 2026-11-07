# xgcpx

## Cloud Run deployer

`deploy-gcp.sh` is a legitimate deployment helper for standard HTTP applications on Google Cloud Run. It supports a local app directory that contains either a supported buildpack app or a `Dockerfile`, and expects the application to listen on port `8080` (Cloud Run uses `PORT` to inject the runtime port).

Requirements:
- Bash
- Google Cloud CLI (`gcloud`)
- An authenticated Google account
- Access to the target Google Cloud project
- Billing enabled for any services that require it

Quick start:

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
bash deploy-gcp.sh --source . --service my-app --region us-central1 --cpu 2 --public false
```

The script can run interactively or via flags. It:
- validates the active account and project
- checks the project’s Cloud Run region list
- auto-detects available regions for the account and project
- prompts for or accepts a service name
- lets you choose a supported CPU tier (1, 2, 4, 6, or 8 vCPU)
- optionally allows public unauthenticated access
- enables the necessary Google APIs
- deploys the app with a zero-to-three instance scale range
- prints the final service URL, region, source path, and deployment summary

Important notes:
- The region list is only an availability hint for the account; Cloud Run still enforces quota and eligibility checks during deployment.
- Cloud Build, Artifact Registry, and Cloud Run usage may incur charges.
- Free-tier limits depend on your account, region, and current Google Cloud terms.
- This project is for standard web app deployment only; it is not a VPN, proxy bypass, tunneling, or traffic-obfuscation tool.

Example with interactive mode:

```bash
bash deploy-gcp.sh
```

Example to list supported Cloud Run regions without deploying:

```bash
bash deploy-gcp.sh --list-regions
```

Example dry run:

```bash
bash deploy-gcp.sh --source . --service demo-app --region us-central1 --cpu 2 --dry-run
```

This repo intentionally stays within legitimate Google Cloud deployment practices and safe web app hosting workflows.