# Terraform / Terragrunt

```bash
# Anything starting with TF_VAR_ is auto-bound to a Terraform input variable.
export TF_VAR_environment=dev
export TF_VAR_region=europe-west1
export TF_VAR_db_password="$(security find-generic-password -s my-tf-db -w)"

# Pin Terraform version (when using tfenv / tenv).
export TFENV_TERRAFORM_VERSION=1.10.2

# Force quiet, machine-readable apply output in scripts.
export TF_CLI_ARGS_apply="-input=false -no-color"

# Terragrunt: cache + log control.
export TERRAGRUNT_DOWNLOAD="$HOME/.terragrunt-cache"
export TERRAGRUNT_LOG_LEVEL=info
```
