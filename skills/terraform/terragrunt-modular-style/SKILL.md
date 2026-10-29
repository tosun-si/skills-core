---
name: terragrunt-modular-style
description: Conventions for structuring Terragrunt repos — file layout (live/ + modules/internal,shared), single foundation SA impersonation model, numbered stacks, dependency block patterns with mocks, generated backend/providers, per-stack state buckets, and tag-driven apply. Trigger when creating, editing, or reviewing terragrunt.hcl / root.hcl / org.hcl, or when designing a new Terragrunt foundation or stack structure.
---

# Terragrunt modular style

Conventions for Terragrunt projects (GCP-flavored but mostly portable). Optimize for: DRY config, clear stack boundaries, one identity for all stacks, no JSON keys.

## File layout

```
<repo>/
├── bootstrap/                ← one-time, run locally (creates seed project + state buckets + foundation SA)
│   ├── 0-cli/                ← gcloud script for the chicken-and-egg bits
│   └── 1-terraform/          ← terraform (not terragrunt) for the foundation SA + WIF + downstream buckets
├── live/                     ← Terragrunt stacks (one LEAF dir = one terraform state)
│   ├── root.hcl              ← backend + provider generation + impersonation
│   ├── org.hcl               ← globals: org_id, billing, prefix, SA emails, WIF pool
│   ├── 1-org/                ← top-level org folders + folder IAM
│   ├── 2-environments/       ← BU/app/env folder hierarchy
│   ├── 3-networks/           ← Shared VPCs + subnets + firewalls + PSA + attachments
│   ├── 4-cicd-sas/           ← per-BU+env CI SAs for app-IaC repos
│   └── 4-projects/           ← GCP projects + AR + per-app sub-units
└── modules/
    ├── internal/             ← foundation-only modules (NOT consumed by app repos)
    └── shared/               ← versioned, consumed by app-IaC repos via Git source ref
```

Numbered stack roots (`1-org`, `2-environments`, …) give visual ordering AND a stable key for stack-to-bucket mapping in `root.hcl`. Numbers can repeat (`4-projects`, `4-cicd-sas`) when stacks are peers but logically belong at the same depth.

## Single foundation SA model

One SA (e.g. `sa-tf-foundation`) impersonated by every stack. Locally: human → impersonate. CI: WIF principal → impersonate. **Same provider config local + CI** — no conditional logic.

In `live/root.hcl`:

```hcl
locals {
  org_vars      = read_terragrunt_config(find_in_parent_folders("org.hcl"))
  stack_root    = split("/", path_relative_to_include())[0]
  stack_to_bucket = {
    "1-org"          = "${local.org_vars.locals.prefix}-tf-state-org"
    "2-environments" = "${local.org_vars.locals.prefix}-tf-state-environments"
    "3-networks"     = "${local.org_vars.locals.prefix}-tf-state-networks"
    "4-projects"     = "${local.org_vars.locals.prefix}-tf-state-projects"
    "4-cicd-sas"     = "${local.org_vars.locals.prefix}-tf-state-projects"
  }
  state_bucket = local.stack_to_bucket[local.stack_root]
  impersonate  = local.org_vars.locals.sa_foundation
}
```

NO per-stack SA splits unless you have a real driver (compliance, multi-team).

## remote_state (the load-bearing block)

```hcl
remote_state {
  backend      = "gcs"
  disable_init = true   # Terragrunt's bucket pre-check uses raw ADC and ignores impersonate_service_account — skip it

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    project                     = local.org_vars.locals.state_project
    location                    = local.org_vars.locals.default_region
    bucket                      = local.state_bucket
    prefix                      = path_relative_to_include()
    impersonate_service_account = local.impersonate   # required — backend ops also impersonate
  }
}
```

**Both `provider` AND backend must impersonate** the same SA. Forgetting one half causes state lock failures or "permission denied" errors that are hard to diagnose.

## Generated providers + versions

Provider versions live in `root.hcl` only — never in module `versions.tf`. Modules are local (Terragrunt-only consumers), so DRY > module portability.

```hcl
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "google" {
      region                      = "${local.org_vars.locals.default_region}"
      impersonate_service_account = "${local.impersonate}"
    }
    provider "google-beta" {
      region                      = "${local.org_vars.locals.default_region}"
      impersonate_service_account = "${local.impersonate}"
    }
  EOT
}

generate "versions" {
  path      = "versions_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    terraform {
      required_version = ">= 1.7"
      required_providers {
        google      = { source = "hashicorp/google",      version = "~> 6.0" }
        google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
      }
    }
  EOT
}
```

## Stack unit (`terragrunt.hcl`) skeleton

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/internal//<module-name>"
}

dependency "upstream" {
  config_path = "../../<upstream-path>"

  mock_outputs = {
    some_output = "mock-value-here"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "plan"]
}

locals {
  org_vars = read_terragrunt_config(find_in_parent_folders("org.hcl"))
}

inputs = {
  some_input = dependency.upstream.outputs.some_output
}
```

- `get_repo_root()` makes module sources portable across the repo (no relative-path math).
- `mock_outputs_allowed_terraform_commands` lets `validate`/`init`/`plan` run before the upstream stack has been applied — critical for CI plan-on-PR flows.
- Each unit's state lives at `prefix = path_relative_to_include()` so leaf paths give disjoint state.

## Sub-units per concern under app projects

Don't put everything for an app in one big terragrunt unit. Split by concern:

```
live/4-projects/<bu>/<app>/<env>/
  ├── project/             ← project + APIs + lien
  ├── artifact-registry/   ← AR repos in that project
  ├── kms/                 ← KMS keyrings
  └── deployer-sa/         ← app's runtime SA
```

Each sub-unit has its own state. A corrupted apply on `kms` doesn't block `project`.

## Apply gating: tag-driven, not merge-driven

For foundation IaC (rare, high-impact changes):

```yaml
on:
  pull_request:
    paths: [live/**, modules/**, .github/workflows/iac.yml]
  push:
    branches: [main]   # plan only
    tags:     ["v*"]   # apply
  workflow_dispatch:
    inputs:
      action: { type: choice, options: [plan, apply] }

jobs:
  apply:
    if: |
      (github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')) ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply')
    environment: prd   # manual approval gate
```

Merge to main only re-plans. Tagging `v*` triggers the apply matrix. The `prd` GitHub Environment adds a human approval step.

## Things to avoid

- **Per-stack SA splits** unless a real driver exists. Adds multi-hop impersonation chains and ref-restriction complexity.
- **Ref-restricted WIF bindings** (e.g. `refs/heads/main` only) — breaks tag-driven apply because tag refs don't match. Use `attribute.repository` instead and gate via workflow `if:`.
- **`versions.tf` inside modules** — modules are local; centralize in `root.hcl` `generate "versions"`.
- **Modules in app-IaC repos consuming `modules/internal/`** — that path assumes foundation's state model. Put cross-repo-consumable modules in `modules/shared/` with a clear contract.
- **Single huge terragrunt unit per app** — split by concern; each gets its own state.
- **Foundation knowing app-internal SA names** — grant cross-project IAM to Google-managed service agents (Cloud Run agent, Compute agent) derived from `project_number`, not user-created runtime SAs.

## CLI version & commands (Terragrunt ≥ 1.0 — the CLI redesign)

As of the CLI redesign (verified on **Terragrunt 1.0.3**), unknown commands are
no longer auto-forwarded and the `*-all` commands are gone. Multi-unit runs now
take `--all` on the `run` command:

| Old (deprecated/removed) | New (≥ 1.0) |
|---|---|
| `terragrunt run-all plan` | `terragrunt run --all plan` |
| `terragrunt run-all apply` | `terragrunt run --all apply` |
| `terragrunt run-all destroy` | `terragrunt run --all destroy` |
| `terragrunt run-all output` | `terragrunt run --all output` |

- **Single-unit commands are unchanged**: `terragrunt plan`, `apply`, `destroy`,
  `validate`, `init`, `output` still work directly from a leaf dir (they're
  shortcuts for `run <cmd>`).
- **Don't follow the error's `run -- run-all` hint** — everything after `--` is
  forwarded verbatim to OpenTofu/Terraform, so `run -- run-all` passes a bogus
  `run-all` subcommand to the IaC tool. The fix is the `--all` *flag*.
- `run --all` walks the dependency graph (mocks make upstream-less
  `validate`/`plan` work — see the stack-unit skeleton).

## Operations

Read [`references/operations.md`](references/operations.md) when running
Terragrunt from a laptop (ADC login, single unit vs `run --all` per env) or when
a cancelled CI run left a stale `.tflock` in the state bucket.
