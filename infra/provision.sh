#!/usr/bin/env bash
# Idempotent one-shot provisioning for a new project created from this template.
#
# WHAT THIS DOES, IN ORDER:
#   1. Creates one Turso database named after this repo (skips if it already
#      exists) and mints a scoped db-auth-token, via infra/lib/turso.sh.
#   2. Deploys the Cloudflare Worker (wrangler deploy) and sets its
#      TURSO_DATABASE_URL / TURSO_AUTH_TOKEN / SESSION_HMAC_SECRET secrets via
#      `wrangler secret put` (ADMIN_USER/ADMIN_PW_HASH are set separately by
#      ./infra/add-user.sh, not here).
#   3. Enables GitHub Pages for this repo (serving frontend/) via the GitHub API.
#   4. Writes the generated non-secret identifiers back as GitHub repo secrets
#      via `gh secret set`, so deploy.yml can find the right Worker/db on every
#      push to main.
#
# REQUIRED ENV (set as org-level GitHub secrets when run from bootstrap.yml, or
# in your own shell when run manually):
#   TURSO_PLATFORM_TOKEN   - Turso Platform API token (Turso dashboard -> Settings)
#   TURSO_ORG              - your Turso organization slug
#   CLOUDFLARE_API_TOKEN   - Cloudflare API token (Workers Scripts + KV + Pages edit)
#   CLOUDFLARE_ACCOUNT_ID  - Cloudflare account id
#
# Requires on PATH: curl, jq, gh, wrangler.
#
# Idempotent: safe to re-run. Existing resources are detected and left alone
# (Turso db, GitHub Pages); secrets are always re-set since `wrangler secret put`
# / `gh secret set` are themselves overwrite-in-place operations.
#
# NOT executed against a real account as part of building this template - see
# README.md, section "Hvad er IKKE bygget/eksekveret i denne skabelon".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/turso.sh
source "${SCRIPT_DIR}/lib/turso.sh"

PROJECT_NAME="${PROJECT_NAME:-$(basename "$REPO_ROOT")}"

main() {
  log_step "Provisioning project '${PROJECT_NAME}'"

  require_cmd curl
  require_cmd jq
  require_cmd gh
  require_cmd wrangler
  require_env TURSO_PLATFORM_TOKEN
  require_env TURSO_ORG
  require_env CLOUDFLARE_API_TOKEN
  require_env CLOUDFLARE_ACCOUNT_ID

  provision_turso_database
  provision_worker
  provision_pages
  write_repo_secrets

  log_step "Provisioning complete for '${PROJECT_NAME}'"
  log_info "Next step: ./infra/add-user.sh to create the first admin login."
}

provision_turso_database() {
  log_step "1/4 Turso database"
  if turso_database_exists "$PROJECT_NAME"; then
    log_info "Database '${PROJECT_NAME}' already exists - skipping create (idempotent)."
  else
    turso_create_database "$PROJECT_NAME" >/dev/null
  fi

  local hostname
  hostname="$(turso_get_hostname "$PROJECT_NAME")"
  TURSO_DATABASE_URL="libsql://${hostname}"
  TURSO_AUTH_TOKEN="$(turso_create_db_token "$PROJECT_NAME")"
  log_info "Turso database URL: ${TURSO_DATABASE_URL}"
}

provision_worker() {
  log_step "2/4 Cloudflare Worker"
  log_info "Deploying Worker '${PROJECT_NAME}' via wrangler..."
  (cd "${REPO_ROOT}/worker" && wrangler deploy --name "$PROJECT_NAME")

  log_info "Setting Worker secrets (idempotent - wrangler secret put overwrites in place)..."
  wrangler_secret_put "TURSO_DATABASE_URL" "$TURSO_DATABASE_URL" "${REPO_ROOT}/worker" "$PROJECT_NAME"
  wrangler_secret_put "TURSO_AUTH_TOKEN" "$TURSO_AUTH_TOKEN" "${REPO_ROOT}/worker" "$PROJECT_NAME"

  local session_secret="${SESSION_HMAC_SECRET:-}"
  if [[ -z "$session_secret" ]]; then
    session_secret="$(openssl rand -base64 32)"
  fi
  wrangler_secret_put "SESSION_HMAC_SECRET" "$session_secret" "${REPO_ROOT}/worker" "$PROJECT_NAME"

  log_info "ADMIN_USER / ADMIN_PW_HASH are set separately: run ./infra/add-user.sh next."
}

provision_pages() {
  log_step "3/4 GitHub Pages"
  local repo_full_name
  repo_full_name="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

  if gh api "repos/${repo_full_name}/pages" >/dev/null 2>&1; then
    log_info "GitHub Pages already enabled - skipping (idempotent)."
  else
    log_info "Enabling GitHub Pages (branch=main, path=/frontend)..."
    gh api "repos/${repo_full_name}/pages" -X POST \
      -f "source[branch]=main" -f "source[path]=/frontend" >/dev/null
  fi
}

write_repo_secrets() {
  log_step "4/4 Writing generated identifiers back as repo secrets"
  gh_secret_set "TURSO_DB_NAME" "$PROJECT_NAME"
  gh_secret_set "CF_WORKER_NAME" "$PROJECT_NAME"
  gh_secret_set "CLOUDFLARE_ACCOUNT_ID" "$CLOUDFLARE_ACCOUNT_ID"
  log_info "TURSO_AUTH_TOKEN / SESSION_HMAC_SECRET stay Worker-only secrets, not duplicated as repo secrets."
}

main "$@"
