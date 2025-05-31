#!/bin/zsh

# Log levels
declare -A LOG_LEVELS=(
  ["ERROR"]=0
  ["WARN"]=1
  ["INFO"]=2
  ["DEBUG"]=3
)

# Default log level
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_FILE="migration_$(date '+%Y%m%d_%H%M%S').log"

# Logging function
log_message() {
  local level="${1:-INFO}"  # Default to INFO if no level specified
  local message="$2"
  
  # Check if we should log this message based on current log level
  if (( ${LOG_LEVELS[$level]} <= ${LOG_LEVELS[$LOG_LEVEL]} )); then
    local log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    echo "$log_entry" | tee -a "$LOG_FILE"
  fi
}

# --- Utility Functions ---

# Check that all required environment variables are set
check_env() {
  local missing=0
  # Loop through required variables
  for var in GITLAB_TOKEN GITHUB_ORG CSV_FILE REPOS_DIR TMP_FILE; do
    # If variable is not set, print error
    if [[ -z "${(P)var}" ]]; then
      log_message "ERROR" "Error: $var is not set. Please set it in your .env file."
      missing=1
    fi
  done
  
  # Ensure GitHub CLI is authenticated with the token
  gh auth status || gh auth login

  # Exit if any variable is missing
  if [[ $missing -eq 1 ]]; then
    exit 1
  fi
}

# Update the step-status column in the CSV for a given slug and step
update_step_status() {
  local slug="$1"   # The repo slug
  local step="$2"   # The step to add (cloned, cleaned, pushed)
  # Use awk to append the step if not already present, preserving history, using '>' as separator
  awk -F, -v OFS="," -v slug="$slug" -v step="$step" '{
    if (NR==1) { print $0; next }
    if ($2==slug && ($3 == "" || $3 ~ /^ *$/)) {
      $3=step
    } else if ($2==slug && index($3, step)==0) {
      $3=$3">"step
    }
    print $0
  }' "$CSV_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CSV_FILE"
}

# Clone a GitLab repo into the repos directory
clone_repo() {
  local repo_url="$1"  # GitLab repo URL
  local slug="$2"      # Directory name (slug)
  log_message "INFO" "Cloning $repo_url into $REPOS_DIR/$slug with all branches and tags ..."

  # Clone using GitLab access token with all branches and tags
  git clone --bare "https://oauth2:${GITLAB_TOKEN}@${repo_url#https://}" "$REPOS_DIR/$slug.git" || return 1

  # # Convert the bare mirror repository to a normal repository
  # cd "$REPOS_DIR/$slug" || return 1
  # git config --unset core.bare || return 1
  # cd - > /dev/null

  return 0
}

# Create and push repo to GitHub
push_to_github() {
  local slug="$1"  # Directory name (slug)
  log_message "INFO" "Pushing $slug to GitHub org $GITHUB_ORG ..."

  # Create repo on GitHub
  gh repo create "$GITHUB_ORG/$slug" --private || return 1
  cd "$REPOS_DIR/$slug.git" || return 1  # Enter repo directory

  # Verify repository integrity and clean up
  # git fsck || return 1
  # git gc --aggressive --prune=all || return 1
  # git repack -a -d --depth=250 --window=250 || return 1

  # Add remote origin
  git remote add github "https://github.com/$GITHUB_ORG/$slug.git" || return 1

  # Detect default branch
  local default_branch
  default_branch=$(git symbolic-ref HEAD | sed 's@^refs/heads/@@')

  # Push default branch first
  if [[ -n "$default_branch" ]]; then
    log_message "INFO" "Pushing default branch $default_branch ..."
    git push github "$default_branch" || return 1
  fi

  # Push all other branches and tags
  log_message "INFO" "Pushing remaining branches and tags ..."
  # git push --mirror || return 1
  git push github --all || return 1
  git push github --tags || return 1

  cd - > /dev/null  # Return to previous directory
  return 0
}

# Main migration process
migrate() {
  mkdir -p "$REPOS_DIR"  # Ensure repos directory exists
  # Read CSV, skip header, and process each repo
  awk -F, 'NR>1 {print $1 "," $2 "," $3}' "$CSV_FILE" | while IFS=',' read -r repo_url slug step_status; do
    # Skip if slug or repo_url is empty or repo_url does not look like a GitLab URL
    if [[ -z "$slug" || -z "$repo_url" || "$repo_url" != https://gitlab.* ]]; then
      continue
    fi
    # Step 1: Clone if not already done
    if [[ "$step_status" != *cloned* ]]; then
      clone_repo "$repo_url" "$slug"
      if [[ $? -eq 0 ]]; then
        update_step_status "$slug" "cloned"
      else
        log_message "ERROR" "Failed to clone $repo_url"
        continue
      fi
    fi
    # Refresh step_status from CSV
    step_status=$(awk -F, -v slug="$slug" '($2==slug){print $3}' "$CSV_FILE" | head -n1)
    # Step 2: Push to GitHub if not already done
    if [[ "$step_status" != *pushed* ]]; then
      push_to_github "$slug"
      if [[ $? -eq 0 ]]; then
        update_step_status "$slug" "pushed"
      else
        log_message "ERROR" "Failed to push $slug to GitHub"
        continue
      fi
    fi
  done
  log_message "INFO" "Migration process finished."
}

# --- Main CLI ---
set -a  # Export all variables from .env
source .env  # Load environment variables
set +a  # Stop exporting all variables

# Parse CLI arguments and run appropriate command
case "$1" in
  help|-h|--help)
    # Print usage and environment variable requirements
    cat <<EOF
Usage: ${0} [command]

Commands:
  migrate   Run the migration process (default)
  help      Show this help message

Environment variables required (in .env):
  GITLAB_TOKEN   GitLab access token
  GITHUB_TOKEN   GitHub access token
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file
  REPOS_DIR      Directory to clone repos into
  TMP_FILE       Temporary file for CSV updates
EOF
    ;;
  migrate|"")
    check_env   # Check environment variables
    migrate     # Run migration
    ;;
  *)
    log_message "ERROR" "Unknown command: $1"  # Handle unknown command
    # Print usage and environment variable requirements
    cat <<EOF
Usage: ${0##*/} [command]

Commands:
  migrate   Run the migration process (default)
  help      Show this help message

Environment variables required (in .env):
  GITLAB_TOKEN   GitLab access token
  GITHUB_TOKEN   GitHub access token
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file
  REPOS_DIR      Directory to clone repos into
  TMP_FILE       Temporary file for CSV updates
EOF
    exit 1
    ;;
esac