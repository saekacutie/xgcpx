#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-gcp.sh [options]

Options:
  --source DIR             Source directory to deploy (default: .)
  --service NAME          Cloud Run service name
  --project ID            Google Cloud project ID
  --region REGION         Cloud Run region (must be supported by the project/account)
  --cpu N                 CPU tier: 1, 2, 4, 6, or 8 (default: 2)
  --memory SIZE           Memory size, e.g. 1Gi, 2Gi, 4Gi, 8Gi (default: auto)
  --public                Allow unauthenticated public access
  --private               Require authenticated access (default)
  --max-instances N       Max scale value (default: 3)
  --min-instances N       Min scale value (default: 0)
  --concurrency N         Requests per instance (default: 80)
  --port PORT             App port (default: 8080)
  --dry-run               Validate inputs without deploying
  --list-regions          List available Cloud Run regions and exit
  --help                  Show this help

Examples:
  bash deploy-gcp.sh --source . --service demo-app --project my-project --region us-central1 --cpu 2 --private
  bash deploy-gcp.sh --list-regions
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

check_requirement() {
  command -v gcloud >/dev/null 2>&1 || die "Google Cloud CLI (gcloud) is required."
}

resolve_cpu_memory() {
  local cpu_value="$1"
  case "$cpu_value" in
    1) printf '%s\n%s\n' "1" "1Gi" ;;
    2) printf '%s\n%s\n' "2" "2Gi" ;;
    4) printf '%s\n%s\n' "4" "4Gi" ;;
    6) printf '%s\n%s\n' "6" "8Gi" ;;
    8) printf '%s\n%s\n' "8" "8Gi" ;;
    *) die "Unsupported CPU tier '$cpu_value'. Choose 1, 2, 4, 6, or 8." ;;
  esac
}

project=""
service=""
source_dir="."
region=""
cpu="2"
memory="2Gi"
allow_public=false
max_instances="3"
min_instances="0"
concurrency="80"
port="8080"
dry_run=false
list_regions=false

while (($#)); do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "Missing value for --source."
      source_dir="$2"
      shift 2
      ;;
    --service)
      [[ $# -ge 2 ]] || die "Missing value for --service."
      service="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || die "Missing value for --project."
      project="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "Missing value for --region."
      region="$2"
      shift 2
      ;;
    --cpu)
      [[ $# -ge 2 ]] || die "Missing value for --cpu."
      cpu="$2"
      shift 2
      ;;
    --memory)
      [[ $# -ge 2 ]] || die "Missing value for --memory."
      memory="$2"
      shift 2
      ;;
    --public)
      allow_public=true
      shift
      ;;
    --private)
      allow_public=false
      shift
      ;;
    --max-instances)
      [[ $# -ge 2 ]] || die "Missing value for --max-instances."
      max_instances="$2"
      shift 2
      ;;
    --min-instances)
      [[ $# -ge 2 ]] || die "Missing value for --min-instances."
      min_instances="$2"
      shift 2
      ;;
    --concurrency)
      [[ $# -ge 2 ]] || die "Missing value for --concurrency."
      concurrency="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "Missing value for --port."
      port="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --list-regions)
      list_regions=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$source_dir" || "$source_dir" == "." ]] && [[ -d "$1" ]]; then
        source_dir="$1"
      else
        die "Unknown argument: $1"
      fi
      shift
      ;;
  esac
done

check_requirement

active_account="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null | head -n 1)"
[[ -n "$active_account" ]] || die "No active gcloud account. Run 'gcloud auth login' first."

if [[ -z "$project" ]]; then
  project="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [[ -z "$project" || "$project" == "(unset)" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Google Cloud project ID: " project
  else
    die "No Google Cloud project ID was provided. Use --project or run 'gcloud config set project YOUR_PROJECT_ID'."
  fi
fi

project="$(trim "$project")"
[[ "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "Invalid Google Cloud project ID: '$project'"
gcloud projects describe "$project" --format='value(projectId)' >/dev/null 2>&1 || die "Project '$project' is unavailable to the active account."

region_output="$(gcloud run regions list --format='value(locationId)' --project "$project" 2>/dev/null)" || die "Could not list Cloud Run regions for project '$project'. Check gcloud access and try again."
mapfile -t regions < <(printf '%s\n' "$region_output" | sort -u | awk 'NF')
((${#regions[@]} > 0)) || die "No Cloud Run regions were returned for project '$project'."

if [[ "$list_regions" == true ]]; then
  printf '\nAvailable Cloud Run regions for project %s:\n' "$project"
  for index in "${!regions[@]}"; do
    printf '  %2d) %s\n' "$((index + 1))" "${regions[$index]}"
  done
  exit 0
fi

if [[ -z "$service" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Cloud Run service name: " service
  else
    die "No Cloud Run service name was provided. Use --service NAME."
  fi
fi
service="$(trim "$service")"
[[ "$service" =~ ^[a-z][a-z0-9-]{0,48}[a-z0-9]$ ]] || die "Use 2-50 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."

[[ -d "$source_dir" ]] || die "Source directory does not exist: $source_dir"
source_dir="$(cd "$source_dir" && pwd)"

if [[ -n "$region" ]]; then
  region="$(trim "$region")"
  if ! printf '%s\n' "${regions[@]}" | grep -Fxq "$region" >/dev/null 2>&1; then
    die "Region '$region' is not available for this project/account. Choose one of: $(printf '%s ' "${regions[@]}")"
  fi
else
  if [[ -t 0 ]]; then
    printf '\nCloud Run regions available for project %s:\n' "$project"
    for index in "${!regions[@]}"; do
      printf '  %2d) %s\n' "$((index + 1))" "${regions[$index]}"
    done
    read -r -p "Select region number: " region_choice
    [[ "$region_choice" =~ ^[0-9]+$ ]] || die "Region selection must be a number."
    ((region_choice >= 1 && region_choice <= ${#regions[@]})) || die "Region selection is out of range."
    region="${regions[$((region_choice - 1))]}"
  else
    die "No region was provided. Use --region REGION."
  fi
fi

if [[ "$cpu" != "" ]]; then
  cpu="$(trim "$cpu")"
  read -r cpu_value memory_value < <(resolve_cpu_memory "$cpu")
  cpu="$cpu_value"
  memory="$memory_value"
fi

if [[ "$allow_public" == true ]]; then
  access_flag="--allow-unauthenticated"
  access_label="public"
else
  access_flag="--no-allow-unauthenticated"
  access_label="authenticated"
fi

if [[ ! -f "$source_dir/Dockerfile" ]] && [[ ! -f "$source_dir/Procfile" ]] && [[ ! -d "$source_dir/.git" ]]; then
  printf 'Warning: %s does not appear to contain a Dockerfile or a classic buildpack app. Cloud Run may still succeed if it is a supported app project.\n' "$source_dir" >&2
fi

cat <<EOF

Deployment summary
  Account: $active_account
  Project: $project
  Service: $service
  Region:  $region
  Source:  $source_dir
  CPU:     $cpu vCPU
  Memory:  $memory
  Access:  $access_label
  Scaling: $min_instances to $max_instances instances
  Port:    $port
  Concurrency: $concurrency

Cloud Run usage and build services can incur charges. Free-tier eligibility and
quotas depend on the account, region, and current Google Cloud terms; this script
does not guarantee a free deployment.
EOF

if [[ "$dry_run" == true ]]; then
  printf '\nDry run successful. No deployment was triggered.\n'
  exit 0
fi

if [[ -t 0 ]]; then
  read -r -p "Deploy now? [y/N]: " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" || "$confirm" == "yes" || "$confirm" == "YES" ]] || die "Deployment cancelled."
else
  printf 'Non-interactive deployment mode selected; continuing without confirmation.\n'
fi

gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  --project "$project" --quiet || die "Could not enable the Cloud Run build APIs."

gcloud run deploy "$service" \
  --source "$source_dir" \
  --project "$project" \
  --region "$region" \
  --platform managed \
  --cpu "$cpu" \
  --memory "$memory" \
  --min "$min_instances" \
  --max "$max_instances" \
  --concurrency "$concurrency" \
  --port "$port" \
  "$access_flag" \
  --quiet || die "Cloud Run deployment failed. Review the gcloud output above."

service_url="$(gcloud run services describe "$service" --project "$project" --region "$region" --format='value(status.url)')" || die "Deployment succeeded, but the service URL could not be retrieved."
[[ -n "$service_url" ]] || die "Deployment succeeded, but Cloud Run returned an empty service URL."

printf '\nDeployment succeeded\n'
printf 'Service: %s\nRegion:  %s\nSource:  %s\nURL:     %s\n' "$service" "$region" "$source_dir" "$service_url"