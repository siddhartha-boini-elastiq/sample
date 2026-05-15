#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT_ID="kanika-agrawal-poc"
REGION="us-central1"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
SA_NAME="gh-actions-terraform"
STATE_BUCKET="kanika-agrawal-poc-tfstate-19b"
GITHUB_REPO="siddhartha-boini-elastiq/sample"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Setting active project to $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Enabling required APIs"
gcloud services enable \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com

echo "==> Creating service account: $SA_NAME"
if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
  echo "    Service account already exists, skipping"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="GitHub Actions Terraform"
fi

echo "==> Granting Storage Admin to service account"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.admin"

echo "==> Creating Workload Identity Pool: $POOL_ID"
if gcloud iam workload-identity-pools describe "$POOL_ID" --location=global &>/dev/null; then
  echo "    Pool already exists, skipping"
else
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --location=global \
    --display-name="GitHub Pool"
fi

echo "==> Creating OIDC Provider: $PROVIDER_ID"
if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
    --location=global \
    --workload-identity-pool="$POOL_ID" &>/dev/null; then
  echo "    Provider already exists, skipping"
else
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --location=global \
    --workload-identity-pool="$POOL_ID" \
    --display-name="GitHub Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'"
fi

echo "==> Binding service account to WIF pool (repo: $GITHUB_REPO)"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

echo "==> Creating Terraform state bucket: $STATE_BUCKET"
if gsutil ls "gs://${STATE_BUCKET}" &>/dev/null; then
  echo "    Bucket already exists, skipping"
else
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${STATE_BUCKET}"
  gsutil versioning set on "gs://${STATE_BUCKET}"
  gsutil ubla set on "gs://${STATE_BUCKET}"
fi

# ── Print GitHub secrets ───────────────────────────────────────────────────────
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo ""
echo "================================================================"
echo "GCP setup complete. Add these two secrets to your GitHub repo:"
echo "  Settings -> Secrets and variables -> Actions -> New repository secret"
echo ""
echo "  WIF_PROVIDER = $WIF_PROVIDER"
echo "  SERVICE_ACCOUNT_EMAIL = $SA_EMAIL"
echo "================================================================"
