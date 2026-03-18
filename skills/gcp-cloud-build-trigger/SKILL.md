---
name: gcp-cloud-build-trigger
description: Set up Cloud Build CI/CD triggers connected to GitHub repositories on GCP. Use this skill whenever the user asks to set up CI/CD, create Cloud Build triggers, connect a GitHub repo to Cloud Build, automate deployments on push, or wire up a deploy pipeline to GCP. Also use when the user mentions "cloudbuild.yaml", "deploy on push to main", or asks about GitHub-to-Cloud-Run deployment automation. This skill handles the full 2nd-gen connection workflow which is non-obvious and error-prone without a guide.
---

# GCP Cloud Build → GitHub Trigger Setup

This skill walks through connecting a GitHub repository to Google Cloud Build and creating an auto-deploy trigger. The process has three sequential steps that must happen in order, with specific IAM permissions needed at each stage.

## Why this skill exists

The Cloud Build GitHub integration uses a "2nd-gen" connection model that differs from the legacy approach. The legacy `--repo-name`/`--repo-owner` flags require a pre-existing OAuth app connection set up in the GCP Console. The 2nd-gen approach (`gcloud builds connections`) can be done entirely from the CLI but has a specific sequence of API enablement, IAM grants, and OAuth steps that are easy to get wrong.

## Before you start

Gather these from the user:

| Parameter | Example | Notes |
|---|---|---|
| GCP Project ID | `my-project` | Must have billing enabled |
| Region | `asia-southeast1` | Where Cloud Build runs |
| GitHub org/user | `myorg` | Owner of the repo |
| GitHub repo | `my-repo` | Repository name |
| Branch pattern | `^main$` | Regex for trigger branch |
| Build config path | `cloudbuild.yaml` | Relative to repo root |

## Step 0: Enable required APIs

```bash
gcloud services enable cloudbuild.googleapis.com --project=$PROJECT_ID
gcloud services enable secretmanager.googleapis.com --project=$PROJECT_ID
```

Secret Manager is required because the 2nd-gen GitHub connection stores the OAuth token there.

## Step 1: Grant Secret Manager permissions to Cloud Build service agent

The Cloud Build **service agent** (not the default compute SA) needs permission to create secrets and set IAM policies on them. This is a setup-time permission that can be revoked afterward.

```bash
# Get the project number
PN=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# The Cloud Build service agent — note this is NOT the compute SA
CB_AGENT="service-${PN}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CB_AGENT}" \
  --role="roles/secretmanager.admin" \
  --condition=None
```

### Common error if you skip this

```
could not assert Secret Manager permissions. Make sure that Secret Manager is
enabled in your GCP project and that the Cloud Build P4SA
(service-NNNNN@gcp-sa-cloudbuild.iam.gserviceaccount.com) has permissions
secretmanager.secrets.create and secretmanager.secrets.setIamPolicy.
```

Fix: run the IAM binding above, then retry.

## Step 2: Create the GitHub connection

```bash
gcloud builds connections create github $CONNECTION_NAME \
  --region=$REGION \
  --project=$PROJECT_ID
```

This will output a URL. The user must open it in their browser, sign into GitHub, and authorize the Cloud Build GitHub App on their org. They may need to install the app on specific repos or the entire org.

**Wait for the user to complete the browser OAuth flow**, then verify:

```bash
gcloud builds connections describe $CONNECTION_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(installationState.stage)"
```

Must return `COMPLETE` before proceeding.

### Common states

| State | Meaning | Action |
|---|---|---|
| `COMPLETE` | Ready to use | Proceed to Step 3 |
| `PENDING_USER_OAUTH` | Waiting for browser auth | User needs to click the link |
| `PENDING_INSTALL_APP` | App not installed on org | User needs to install GitHub App |

## Step 3: Link the repository

```bash
gcloud builds repositories create $REPO_NAME \
  --remote-uri=https://github.com/$GITHUB_ORG/$REPO_NAME.git \
  --connection=$CONNECTION_NAME \
  --region=$REGION \
  --project=$PROJECT_ID
```

This creates a Cloud Build repository resource linked to the GitHub repo through the connection.

## Step 4: Create the trigger

The key difference from legacy: use the `--repository` flag with the **full 2nd-gen resource path**, not `--repo-name`/`--repo-owner`.

```bash
# The service account that Cloud Build will use to deploy
# Often the default compute SA, but can be a dedicated one
DEPLOY_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud builds triggers create github \
  --name=$TRIGGER_NAME \
  --repository="projects/$PROJECT_ID/locations/$REGION/connections/$CONNECTION_NAME/repositories/$REPO_NAME" \
  --branch-pattern="$BRANCH_PATTERN" \
  --build-config=$BUILD_CONFIG_PATH \
  --region=$REGION \
  --project=$PROJECT_ID \
  --service-account="projects/$PROJECT_ID/serviceAccounts/$DEPLOY_SA"
```

### Common error: INVALID_ARGUMENT

If you see `INVALID_ARGUMENT` when creating the trigger, it usually means:
- You used the legacy `--repo-name`/`--repo-owner` flags instead of `--repository`
- The repository resource path is malformed
- The connection isn't in `COMPLETE` state
- The repository link from Step 3 wasn't created

### The `--service-account` flag

Required for 2nd-gen triggers. This is the SA that Cloud Build assumes when executing the build steps. It needs whatever permissions your `cloudbuild.yaml` requires (e.g., `roles/run.admin` for Cloud Run deploys, `roles/artifactregistry.writer` for pushing images).

## Step 5: Revoke elevated permissions

The Secret Manager Admin role was only needed for connection setup. Revoke it now:

```bash
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CB_AGENT}" \
  --role="roles/secretmanager.admin"
```

## Verification

Confirm the trigger is active:

```bash
gcloud builds triggers list --project=$PROJECT_ID --region=$REGION
```

Test it by pushing a commit to the target branch:

```bash
gcloud builds list --project=$PROJECT_ID --region=$REGION --limit=5
```

## Quick reference: cloudbuild.yaml for Cloud Run

A typical multi-service deploy config:

```yaml
steps:
  # Build images (parallel)
  - name: gcr.io/cloud-builders/docker
    args: [build, -t, "$_IMAGE_TAG", -f, path/to/Dockerfile, context/dir]
    id: build-svc

  # Push images
  - name: gcr.io/cloud-builders/docker
    args: [push, "$_IMAGE_TAG"]
    id: push-svc
    waitFor: [build-svc]

  # Deploy to Cloud Run
  - name: gcr.io/google.com/cloudsdktool/cloud-sdk
    entrypoint: gcloud
    args:
      - run
      - deploy
      - my-service
      - --image=$_IMAGE_TAG
      - --region=$_REGION
      - --project=$PROJECT_ID
    id: deploy-svc
    waitFor: [push-svc]

substitutions:
  _REGION: asia-southeast1
  _IMAGE_TAG: asia-southeast1-docker.pkg.dev/${PROJECT_ID}/my-repo/my-image:${SHORT_SHA}

images:
  - $_IMAGE_TAG

options:
  logging: CLOUD_LOGGING_ONLY
```

Use `waitFor` to express dependencies — steps without dependencies run in parallel. `${SHORT_SHA}` and `${PROJECT_ID}` are built-in substitutions provided by Cloud Build.
