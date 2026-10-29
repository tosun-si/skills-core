# Terragrunt operations

## Local iteration

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project <seed-project>

# Single unit (impersonates the foundation SA via root.hcl):
cd live/<stack>
terragrunt plan
terragrunt apply

# Whole env, dependency-ordered:
cd live/<env>
terragrunt run --all plan
terragrunt run --all apply
```

Group-based `iam.serviceAccountTokenCreator` on the foundation SA: humans in the admins group can impersonate locally. No personal IAM bindings.

## Stale state lock cleanup

If a CI run is cancelled mid-plan, the `.tflock` file persists. To find/remove:

```bash
gcloud storage ls "gs://<state-bucket>/**/*.tflock"
gcloud storage rm "gs://<state-bucket>/<path>/default.tflock"
```

Cleaner than `force-unlock` for the GCS backend; the lock ID isn't needed.
