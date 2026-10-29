# GCP (`gcloud`, ADC, impersonation)

```bash
# Make every gcloud / google-cloud-* SDK call use this project by default.
export CLOUDSDK_CORE_PROJECT=my-dev-project
export CLOUDSDK_COMPUTE_REGION=europe-west1

# Application Default Credentials — pin to a key file (rare; prefer ADC login).
# export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/keys/my-sa.json"

# Force every SDK call to impersonate a service account (the right way
# for IaC / cross-env work — no key files on disk).
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=sa-foo-dev@my-seed-project.iam.gserviceaccount.com
```

`gcloud` also honours named **configurations** (`gcloud config configurations
activate <name>`). If you switch configs often, set
`CLOUDSDK_ACTIVE_CONFIG_NAME=<name>` in `.envrc` instead of activating
manually.
