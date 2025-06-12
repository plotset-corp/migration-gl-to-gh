# GitLab to GitHub Migration Tool

This project provides a CLI tool to automate the migration of repositories from GitLab to GitHub. It handles cloning repositories and pushing them to a GitHub organization.

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Setup](#setup)
- [Usage](#usage)
- [CSV File Details](#csv-file-details)
- [Additional Permissions](#additional-permissions)
- [Logging](#logging)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributing](#contributing)
- [Contact](#contact)

## Features
- Clone repositories from GitLab.
- Push repositories to GitHub.
- Track migration progress using a CSV file.

**Note:** The cleanup step has been removed to retain all branches for maintenance purposes.

## Requirements

Before using this tool, ensure you have the following:

1. **Environment Variables**:
   - `GITLAB_TOKEN`: GitLab access token.
   - `GITHUB_ORG`: GitHub organization name.
   - `CSV_FILE`: Path to the CSV file containing repository details.
   - `REPOS_DIR`: Directory to clone repositories into.
   - `TMP_FILE`: Temporary file for CSV updates.

2. **Tools**:
   - Git installed on your system.
   - GitHub CLI (`gh`) installed and authenticated.
   - `git-filter-repo` installed:
     - For macOS: `brew install git-filter-repo`
     - For Ubuntu: `sudo apt install python3 && pip3 install git-filter-repo`

3. **CSV File Format**:
   - The CSV file should have the following columns:
     - `repo_url`: URL of the GitLab repository.
     - `slug`: Directory name for the repository.
     - `step_status`: Migration status (e.g., `cloned`, `pushed`).

## Setup

Follow these steps to set up the migration tool:

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd migration
   ```

2. Create a `.env` file in the project directory and define the required environment variables:
   ```bash
   GITLAB_TOKEN=<your-gitlab-token>
   GITHUB_ORG=<your-github-organization>
   CSV_FILE=<path-to-your-csv-file>
   REPOS_DIR=<path-to-repos-directory>
   TMP_FILE=<path-to-temporary-file>
   ```

3. Ensure the CSV file is properly formatted and contains the required columns.

4. Make the script executable:
   ```bash
   chmod +x start.sh
   ```

## Usage

Run the migration tool using the following commands:

### Help
To display help information:
```bash
./start.sh help
```

### Migration
To start the migration process:
```bash
./start.sh migrate
```

## CSV File Details

The CSV file tracks the migration progress for each repository. The `step_status` column indicates the current status:
- `cloned`: Repository has been cloned from GitLab.
- `pushed`: Repository has been pushed to GitHub.

## Additional Permissions

### GitHub CLI Permissions
To delete repositories on GitHub, ensure the GitHub CLI (`gh`) has the necessary permissions. You may need to authenticate with elevated access:
```bash
gh auth refresh -s delete_repo
```
This grants the ability to delete repositories using the CLI.

## Logging

Logs are saved in files named `migration_<timestamp>.log` in the project directory. These logs provide detailed information about the migration process.

## Troubleshooting

### Missing Environment Variables
If any required environment variables are missing, the tool will log an error and exit. Ensure all variables are defined in the `.env` file.

### GitHub CLI Authentication
Ensure the GitHub CLI is authenticated using the provided token:
```bash
gh auth login
```

### CSV File Issues
Ensure the CSV file is properly formatted and contains valid GitLab repository URLs.

## Known Issues
- **Large Repository Sizes**: Migration may take longer for repositories with large histories.
- **Rate Limits**: Ensure your GitHub and GitLab tokens have sufficient API rate limits.

## License

This project is licensed under the MIT License.

## Contributing

Feel free to submit issues or pull requests to improve this tool.

## Contact

For questions or support, contact [owner](mailto:hello@plotset.com). Alternatively, open an issue in the repository.
