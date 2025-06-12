#!/usr/bin/zsh

# Log levels
declare -A LOG_LEVELS=(
  ["ERROR"]=0
  ["WARN"]=1
  ["INFO"]=2
  ["DEBUG"]=3
)

# Default log level
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_FILE="delete_repos_$(date '+%Y%m%d_%H%M%S').log"

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

# Delete a GitHub repo
delete_repo() {
  local repo_name="$1"  # GitHub repo name
  log_message "INFO" "Deleting repo $repo_name from GitHub org $GITHUB_ORG ..."

  # Delete repo using GitHub CLI
  gh repo delete "$GITHUB_ORG/$repo_name" --yes
  if [[ $? -eq 0 ]]; then
    log_message "INFO" "Successfully deleted $repo_name."
  else
    log_message "ERROR" "Failed to delete $repo_name."
  fi
}

# Delete a single GitHub repository directly
delete_single() {
  local repo_name="$1"  # GitHub repo name
  
  if [[ -z "$repo_name" ]]; then
    log_message "ERROR" "Repository name is required for single deletion"
    log_message "INFO" "Usage: $0 delete-single <repo-name>"
    return 1
  fi
  
  log_message "INFO" "Starting single repository deletion: $repo_name"
  
  # Delete the repository
  delete_repo "$repo_name"
  
  log_message "INFO" "Single repository deletion completed."
  return 0
}

# Main deletion process
delete_all_repos() {
  log_message "INFO" "Starting deletion process for all repos in $CSV_FILE ..."

  # Read CSV, skip header, and process each repo
  awk -F, 'NR>1 {print $2}' "$CSV_FILE" | while read -r repo_name; do
    # Skip if repo_name is empty
    if [[ -z "$repo_name" ]]; then
      log_message "WARN" "[SKIP] Empty repo name in CSV."
      continue
    fi

    # Delete repo
    delete_repo "$repo_name"
  done

  log_message "INFO" "Deletion process finished."
}

# --- Main CLI ---
set -a  # Export all variables from .env
source .env  # Load environment variables
set +a  # Stop exporting all variables

# Parse CLI arguments and run appropriate command
case "$1" in
  help|-h|--help)
    cat <<EOF
Usage: $0 [command]

Commands:
  delete               Run the deletion process using CSV file (default)
  delete-single <repo> Delete a single repository directly
                       - repo: Repository name (without organization prefix)
  help                 Show this help message

Environment variables required (in .env):
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file (for delete command)
EOF
    ;;
  delete|"")
    delete_all_repos  # Run deletion
    ;;
  delete-single)
    delete_single "$2"  # Run single repository deletion
    ;;
  *)
    log_message "ERROR" "Unknown command: $1"  # Handle unknown command
    cat <<EOF
Usage: $0 [command]

Commands:
  delete               Run the deletion process using CSV file (default)
  delete-single <repo> Delete a single repository directly
  help                 Show this help message

Environment variables required (in .env):
  GITHUB_ORG     GitHub organization name
  CSV_FILE       Path to the CSV file (for delete command)
EOF
    exit 1
    ;;
esac
