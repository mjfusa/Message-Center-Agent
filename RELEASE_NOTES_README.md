# Release Notes Generator

This directory contains a PowerShell script to automatically generate release notes from Git commits.

## Overview

The `GenerateReleaseNotes.ps1` script analyzes the git commit history and generates a formatted release notes document in Markdown format. It categorizes commits by type (Features, Bug Fixes, Cleanup, etc.) and includes links to the commits on GitHub.

## Prerequisites

- PowerShell (PowerShell Core 7+ or Windows PowerShell 5.1+)
- Git
- A local clone of the repository

## Usage

### Basic Usage

Generate release notes for commits from the last day:

```powershell
.\GenerateReleaseNotes.ps1
```

This will create a `RELEASE_NOTES.md` file in the current directory with commits from the last 24 hours.

### Advanced Usage

#### Specify a Different Time Period

Generate release notes for the last 7 days:

```powershell
.\GenerateReleaseNotes.ps1 -Days 7
```

#### Specify a Custom Output File

Generate release notes to a custom file:

```powershell
.\GenerateReleaseNotes.ps1 -OutputFile "WEEKLY_NOTES.md"
```

#### Analyze a Different Branch

Generate release notes from a different branch:

```powershell
.\GenerateReleaseNotes.ps1 -Branch "develop"
```

#### Combined Parameters

```powershell
.\GenerateReleaseNotes.ps1 -Days 30 -OutputFile "MONTHLY_RELEASE_NOTES.md" -Branch "main"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Days` | Integer | 1 | Number of days to look back for commits |
| `-OutputFile` | String | RELEASE_NOTES.md | Path to the output file |
| `-Branch` | String | main | Git branch to analyze |

## Output Format

The generated release notes include:

- **Header**: Metadata including generation date, time period, and branch
- **Categorized Commits**: Commits grouped by type with emoji indicators
- **Commit Details**: For each commit:
  - Commit SHA (linked to GitHub)
  - Commit message
  - Author name
  - Date and time
  - File change statistics
- **Footer**: Auto-generation notice

### Commit Categories

The script automatically categorizes commits based on conventional commit messages or keywords:

- ✨ **Features**: `feat:`, `feature:`
- 🐛 **Bug Fixes**: `fix:`, `bugfix:`
- 📚 **Documentation**: `docs:`, `documentation:`
- ⚡ **Performance**: `perf:`, `performance:`
- ♻️ **Refactoring**: `refactor:`
- 🧹 **Cleanup**: `cleanup`, `clean up`
- 📦 **Updates**: `update`, `bump`, `version`
- 🔀 **Merges**: `merge`
- 🔨 **Build**: `build:`
- 👷 **CI/CD**: `ci:`
- ✅ **Tests**: `test:`
- 💎 **Style**: `style:`
- 🔧 **Chore**: `chore:`
- 📝 **Other Changes**: Everything else

## Example Output

```markdown
# Release Notes

**Generated:** 2025-10-27 18:24:15 UTC
**Period:** Last 1 day(s)
**Branch:** main
**Total Commits:** 1

## 🧹 Cleanup

- **[37a3a96](https://github.com/mjfusa/Message-Center-Agent/commit/37a3a96)** Clean up repo
  - *Author:* Mike Francis
  - *Date:* 2025-10-27 11:05:37 -0700
  - *Changes:* 78 files changed, 113957 insertions(+)

---

*This release notes document was automatically generated from git commits.*
```

## Integration with CI/CD

You can integrate this script into your GitHub Actions or other CI/CD pipelines:

### GitHub Actions Example

```yaml
name: Generate Release Notes

on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
  workflow_dispatch:  # Manual trigger

jobs:
  release-notes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Fetch all history
      
      - name: Generate Release Notes
        shell: pwsh
        run: |
          ./GenerateReleaseNotes.ps1 -Days 1
      
      - name: Commit Release Notes
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add RELEASE_NOTES.md
          git commit -m "docs: Update release notes" || echo "No changes"
          git push
```

## Tips

1. **Conventional Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/) format for better categorization:
   - `feat: add new feature`
   - `fix: resolve bug in login`
   - `docs: update README`

2. **Regular Generation**: Run the script regularly (e.g., weekly) to maintain up-to-date release notes

3. **Version Releases**: Use the script before creating version tags or releases:
   ```powershell
   .\GenerateReleaseNotes.ps1 -Days 30 -OutputFile "v1.2.0-RELEASE-NOTES.md"
   ```

## Troubleshooting

### "Not in a git repository"

Make sure you run the script from within the git repository directory:

```powershell
cd /path/to/Message-Center-Agent
.\GenerateReleaseNotes.ps1
```

### "No commits found"

This means there are no commits in the specified time period. Try:
- Increasing the `-Days` parameter
- Checking that you're on the correct branch
- Verifying commits exist: `git log --since="1 day ago"`

### Missing commit links

If commit links don't appear, ensure your repository has a GitHub remote:

```bash
git remote -v
```

Should show a GitHub URL like:
```
origin  https://github.com/mjfusa/Message-Center-Agent.git (fetch)
```

## License

This script is part of the Message Center Agent repository and follows the same license.
