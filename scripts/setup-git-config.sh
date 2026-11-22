#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install-git-config.sh — Git configuration and SSH signing setup
# =============================================================================
# Usage: ./install-git-config.sh
# Depends on: bash >= 4.3 (local -n, ${var,,}), git, rbw, date
#
# Functions defined here:
#   setup_git_config() — applies global Git settings and SSH signing
# =============================================================================

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "Error: bash >= 4.3 is required (found ${BASH_VERSION})." >&2
    exit 1
fi


# =============================================================================
# CONFIGURATION — edit strings here without touching the logic below
# =============================================================================

# --- Git defaults -------------------------------------------------------------
readonly CFG_DEFAULT_BRANCH="main"
readonly CFG_DEFAULT_EDITOR="${EDITOR:-nano}"
readonly CFG_ALLOWED_SIGNERS_FILE="$HOME/.ssh/allowed_signers"
# Name of the Bitwarden entry that holds the PUBLIC signing key (ssh-ed25519 AAAA...)
readonly CFG_BW_SIGNING_ENTRY="signingkey"

# --- Prompts ------------------------------------------------------------------
readonly MSG_PROMPT_NAME="Enter your Git username"
readonly MSG_PROMPT_EMAIL="Enter your Git email"
readonly MSG_PROMPT_CONFIRM="Apply these settings? [y/N]: "

# --- Info / success -----------------------------------------------------------
readonly MSG_START="Configuring global Git settings in ~/.gitconfig..."
readonly MSG_SIGNING="Configuring SSH commit signing..."
readonly MSG_SIGNERS="Setting up $CFG_ALLOWED_SIGNERS_FILE..."
readonly MSG_SIGNERS_EXISTS="Entry already present in $CFG_ALLOWED_SIGNERS_FILE, skipping."
readonly MSG_UNLOCKING="Bitwarden vault is locked, unlocking..."
readonly MSG_SUCCESS="Global Git configuration and SSH signing setup applied."

# --- Errors -------------------------------------------------------------------
readonly MSG_ERR_NAME_EMPTY="Error: Username cannot be empty."
readonly MSG_ERR_EMAIL_INVALID="Error: Email format is invalid (expected user@domain.tld)."
readonly MSG_ERR_GIT_CONFIG="Error: Failed to apply git config."
readonly MSG_ERR_LOCKED="Error: Could not unlock the Bitwarden vault (rbw unlock failed)."
readonly MSG_ERR_RBW_GET="Error: rbw could not read entry '$CFG_BW_SIGNING_ENTRY'."
readonly MSG_ERR_KEY_EMPTY="Error: Bitwarden entry '$CFG_BW_SIGNING_ENTRY' is empty."
readonly MSG_ERR_KEY_PRIVATE="Error: Entry '$CFG_BW_SIGNING_ENTRY' looks like a PRIVATE key. Store only the public key there."
readonly MSG_CANCELLED="Cancelled. No changes were made."


# =============================================================================
# HELPERS
# =============================================================================

log() {
    echo "[$(date +%H:%M:%S)] $*"
}

err() {
    echo "[$(date +%H:%M:%S)] $*" >&2
}

# Apply a global git setting; log and fail on error.
# Usage: gset <git config args...>
gset() {
    git config --global "$@" || { err "$MSG_ERR_GIT_CONFIG"; return 1; }
}

# Prompt with optional default value shown in brackets.
# Usage: prompt_with_default <var_name> <message> [default]
prompt_with_default() {
    local -n _ref=$1
    local message=$2
    local default=${3:-}
    local hint=""

    [[ -n "$default" ]] && hint=" [$default]"
    read -rp "${message}${hint}: " _ref
    _ref="${_ref:-$default}"
}

# Validate non-empty string.
validate_not_empty() {
    local value=$1
    local err_msg=$2
    if [[ -z "$value" ]]; then
        echo "$err_msg" >&2
        return 1
    fi
}

# Validate email format.
validate_email() {
    local value=$1
    if [[ ! "$value" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        echo "$MSG_ERR_EMAIL_INVALID" >&2
        return 1
    fi
}

# Fetch the public signing key from Bitwarden and print it to stdout.
# Fails with a specific message for: locked vault, rbw error, empty value,
# or a private key stored by mistake.
fetch_signing_key() {
    local key rbw_err

    if ! rbw unlocked >/dev/null 2>&1; then
        err "$MSG_UNLOCKING"
        rbw unlock || { err "$MSG_ERR_LOCKED"; return 1; }
    fi

    rbw_err=$(mktemp)
    if ! key=$(rbw get "$CFG_BW_SIGNING_ENTRY" 2>"$rbw_err"); then
        err "$MSG_ERR_RBW_GET"
        [[ -s "$rbw_err" ]] && err "  $(<"$rbw_err")"
        rm -f "$rbw_err"
        return 1
    fi
    rm -f "$rbw_err"

    if [[ -z "$key" ]]; then
        err "$MSG_ERR_KEY_EMPTY"
        return 1
    fi

    if [[ "$key" == *"PRIVATE KEY"* ]]; then
        err "$MSG_ERR_KEY_PRIVATE"
        return 1
    fi

    printf '%s' "$key"
}


# =============================================================================
# MAIN
# =============================================================================

# -----------------------------------------------------------------------------
# setup_git_config — configures user info, editor, init, and SSH commit signing
# Reads CFG_DEFAULT_EDITOR. The PUBLIC signing key is taken from Bitwarden
# (via rbw); the matching PRIVATE key must be available in the ssh-agent.
# All settings are applied globally to ~/.gitconfig.
# -----------------------------------------------------------------------------
setup_git_config() {
    log "$MSG_START"
    echo ""

    # --- Fetch signing key first: fail before changing anything ---------------
    local signing_key
    signing_key=$(fetch_signing_key) || return 1

    # --- Collect current values as defaults -----------------------------------
    local current_name current_email
    current_name=$(git config --global user.name  2>/dev/null || true)
    current_email=$(git config --global user.email 2>/dev/null || true)

    # --- Interactive input with validation ------------------------------------
    local git_username=""
    while true; do
        prompt_with_default git_username "$MSG_PROMPT_NAME" "$current_name"
        validate_not_empty "$git_username" "$MSG_ERR_NAME_EMPTY" && break
    done

    local git_email=""
    while true; do
        prompt_with_default git_email "$MSG_PROMPT_EMAIL" "$current_email"
        validate_email "$git_email" && break
    done

    # --- Confirmation ---------------------------------------------------------
    echo ""
    echo "  name  : $git_username"
    echo "  email : $git_email"
    echo "  editor: $CFG_DEFAULT_EDITOR"
    echo "  branch: $CFG_DEFAULT_BRANCH"
    echo ""
    read -rp "$MSG_PROMPT_CONFIRM" confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "$MSG_CANCELLED"
        return 0
    fi
    echo ""

    # --- Apply base config ----------------------------------------------------
    gset user.name          "$git_username"       || return 1
    gset user.email         "$git_email"          || return 1
    gset core.editor        "$CFG_DEFAULT_EDITOR" || return 1
    gset init.defaultBranch "$CFG_DEFAULT_BRANCH" || return 1

    # --- SSH signing ----------------------------------------------------------
    log "$MSG_SIGNING"
    gset user.signingkey "key::${signing_key}" || return 1
    gset gpg.format      "ssh"                 || return 1
    gset commit.gpgsign  "true"                || return 1

    # --- Allowed signers (append, never overwrite) ----------------------------
    log "$MSG_SIGNERS"
    mkdir -p "$HOME/.ssh"
    local entry="${git_email} ${signing_key}"
    if grep -qxF "$entry" "$CFG_ALLOWED_SIGNERS_FILE" 2>/dev/null; then
        log "$MSG_SIGNERS_EXISTS"
    else
        echo "$entry" >> "$CFG_ALLOWED_SIGNERS_FILE"
    fi
    gset gpg.ssh.allowedSignersFile "$CFG_ALLOWED_SIGNERS_FILE" || return 1

    log "$MSG_SUCCESS"
}

# Execute the installation function
setup_git_config
