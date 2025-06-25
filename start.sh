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

# Ensure log directory exists and set log file path
LOG_DIR="log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/migration_$(date '+%Y%m%d_%H%M%S').log"

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
  local required_vars=()
  
  # Determine which variables are required based on command
  if [[ "$1" == "migrate" ]]; then
    required_vars=(GITLAB_TOKEN GITHUB_ORG CSV_FILE REPOS_DIR TMP_FILE)
  else
    # For direct/migrate-single commands
    required_vars=(GITLAB_TOKEN GITHUB_ORG REPOS_DIR)
  fi
  
  # Loop through required variables
  for var in "${required_vars[@]}"; do
    # If variable is not set, print error
    if [[ -z "${(P)var}" ]]; then
      log_message "ERROR" "Error: $var is not set. Please set it in your .env file."
      missing=1
    fi
  done
  
  # Ensure GitHub CLI is authenticated
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

  return 0
}

# Create and push repo to GitHub
push_to_github() {
  local slug="$1"  # Directory name (slug)
  log_message "INFO" "Pushing $slug to GitHub org $GITHUB_ORG ..."

  # Create repo on GitHub
  gh repo create "$GITHUB_ORG/$slug" --private || return 1
  cd "$REPOS_DIR/$slug.git" || return 1  # Enter repo directory

  # Remove commit authors
  log_message "INFO" "Removing commit authors before pushing to GitHub..."
  git filter-repo --replace-refs delete-no-add --commit-callback "
commit.author_name = b\"${GIT_AUTHOR_NAME}\"
commit.author_email = b\"${GIT_AUTHOR_EMAIL}\"
commit.committer_name = b\"${GIT_AUTHOR_NAME}\"
commit.committer_email = b\"${GIT_AUTHOR_EMAIL}\"
" || return 1

  # Verify repository integrity and clean up
  log_message "INFO" "Repository $slug cleaned and ready for push."
  git fsck || return 1
  git gc --aggressive --prune=all || return 1
  git repack -a -d --depth=250 --window=250 || return 1

  # Add remote origin
  log_message "INFO" "Adding GitHub remote origin for $slug to https://github.com/$GITHUB_ORG/$slug.git ..."
  git remote add github "https://github.com/$GITHUB_ORG/$slug.git" || return 1

  # Detect default branch
  local default_branch
  default_branch=$(git symbolic-ref HEAD | sed 's@^refs/heads/@@')
  log_message "INFO" "Detected default branch: $default_branch"

  # Push default branch first
  if [[ -n "$default_branch" ]]; then
    log_message "INFO" "Pushing default branch $default_branch ..."
    git push github "$default_branch" || return 1
  fi

  # Push all other branches and tags
  log_message "INFO" "Pushing remaining branches and tags ..."
  git push github --all || return 1
  git push github --tags || return 1

  cd - > /dev/null  # Return to previous directory
  return 0
}

# Function to migrate a single repository directly
migrate_single() {
  local repo_url="$1"  # GitLab repo URL
  local slug="$2"      # Directory name (slug)
  
  log_message "INFO" "Starting direct migration of $repo_url to GitHub as $slug"
  
  mkdir -p "$REPOS_DIR"  # Ensure repos directory exists
  
  # Step 1: Clone repository
  log_message "INFO" "Cloning repository..."
  clone_repo "$repo_url" "$slug"
  if [[ $? -ne 0 ]]; then
    log_message "ERROR" "Failed to clone $repo_url"
    return 1
  fi
  
  # Step 2: Push to GitHub
  log_message "INFO" "Pushing to GitHub as $slug..."
  push_to_github "$slug"
  if [[ $? -ne 0 ]]; then
    log_message "ERROR" "Failed to push $slug to GitHub"
    return 1
  fi
  
  log_message "INFO" "Direct migration completed successfully."
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
  migrate              Run the migration process using CSV file (default)
  migrate-single <repo_url> <slug>   Migrate a single repository directly
  direct <url> <slug>  Migrate a single repository directly (same as migrate-single)
                       - url: GitLab repository URL
                       - slug: Directory name for local clone and GitHub repo name
  help                 Show this help message

Environment variables required (in .env):
  GITLAB_TOKEN   GitLab access token
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file (for migrate command)
  REPOS_DIR      Directory to clone repos into
  TMP_FILE       Temporary file for CSV updates (for migrate command)
EOF
    ;;
  migrate|"")
    check_env "migrate"   # Check environment variables for migrate command
    migrate     # Run migration
    ;;
  migrate-single|direct)
    check_env "direct"   # Check environment variables for direct migration
    migrate_single "$2" "$3"  # Run single repository migration
    ;;
  *)
    log_message "ERROR" "Unknown command: $1"  # Handle unknown command
    # Print usage and environment variable requirements
    cat <<EOF
Usage: ${0##*/} [command]

Commands:
  migrate              Run the migration process using CSV file (default)
  direct <url> <slug>  Migrate a single repository directly
  migrate-single <repo_url> <slug>   Migrate a single repository directly
  help                 Show this help message

Environment variables required (in .env):
  GITLAB_TOKEN   GitLab access token
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file (for migrate command)
  REPOS_DIR      Directory to clone repos into
  TMP_FILE       Temporary file for CSV updates (for migrate command)
EOF
    exit 1
    ;;
esac