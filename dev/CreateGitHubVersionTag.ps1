<#
.SYNOPSIS
    Creates a new GitHub release with version tag from .env.production.sample.

.DESCRIPTION
    This script reads the AGENT_VERSION from env/.env.production.sample file,
    creates a new Git tag with a version number prefixed with 'v', 
    pushes it to the remote repository, and creates a GitHub release.

.PARAMETER Message
    Optional tag message/annotation. If provided, creates an annotated tag.

.PARAMETER Push
    If specified, automatically pushes the tag to the remote repository.

.PARAMETER CreateRelease
    If specified, creates a GitHub release using GitHub CLI (gh).

.PARAMETER ReleaseNotesFile
    Path to a file containing release notes (markdown format). If not specified and CreateRelease is used,
    GitHub will auto-generate release notes.

.EXAMPLE
    .\CreateGitHubVersionTag.ps1 -Push -CreateRelease
    Creates tag, pushes it, and creates a GitHub release with auto-generated notes

.EXAMPLE
    .\CreateGitHubVersionTag.ps1 -Push -CreateRelease -ReleaseNotesFile "RELEASE_NOTES.md"
    Creates tag, pushes it, and creates a GitHub release using notes from file

.EXAMPLE
    .\CreateGitHubVersionTag.ps1 -Message "Release version 2.0.2" -Push -CreateRelease -ReleaseNotesFile "CHANGELOG.md"
    Creates an annotated tag with message, pushes it, and creates GitHub release with changelog
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Optional tag message for annotated tag")]
    [string]$Message,

    [Parameter(Mandatory = $false, HelpMessage = "Push tag to remote repository")]
    [switch]$Push,

    [Parameter(Mandatory = $false, HelpMessage = "Create a GitHub release")]
    [switch]$CreateRelease,

    [Parameter(Mandatory = $false, HelpMessage = "Path to file containing release notes")]
    [string]$ReleaseNotesFile
)

# Ensure we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Error "Not in a git repository. Please run this script from the repository root."
    exit 1
}

# Read version from .env.production.sample
$envFile = "env\.env.production.sample"
if (-not (Test-Path $envFile)) {
    Write-Error "Could not find $envFile. Please ensure the file exists."
    exit 1
}

# Parse AGENT_VERSION from the file
$content = Get-Content $envFile -Raw
if ($content -match 'AGENT_VERSION\s*=\s*([0-9.]+)') {
    $Version = $matches[1]
    Write-Host "Found version in $envFile $Version" -ForegroundColor Cyan
}
else {
    Write-Error "Could not find AGENT_VERSION in $envFile"
    exit 1
}

# Add 'v' prefix to version
$tagName = "v$Version"

Write-Host "Creating tag: $tagName" -ForegroundColor Cyan

try {
    # Check if tag already exists
    $existingTag = git tag -l $tagName
    if ($existingTag) {
        Write-Error "Tag '$tagName' already exists. Please use a different version number."
        exit 1
    }

    # Create the tag
    if ($Message) {
        # Create annotated tag with message
        git tag -a $tagName -m $Message
        Write-Host "Created annotated tag '$tagName' with message: $Message" -ForegroundColor Green
    }
    else {
        # Create lightweight tag
        git tag $tagName
        Write-Host "Created lightweight tag '$tagName'" -ForegroundColor Green
    }

    # Push to remote if specified
    if ($Push) {
        Write-Host "Pushing tag to remote..." -ForegroundColor Cyan
        git push origin $tagName
        Write-Host "Tag '$tagName' pushed to remote repository" -ForegroundColor Green
    }
    else {
        Write-Host "Tag created locally. Use 'git push origin $tagName' to push it to remote." -ForegroundColor Yellow
    }

    # Create GitHub release if specified
    if ($CreateRelease) {
        # Check if GitHub CLI is installed
        $ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $ghInstalled) {
            Write-Error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com/"
            exit 1
        }

        # Ensure tag is pushed before creating release
        if (-not $Push) {
            Write-Host "Pushing tag to remote (required for release)..." -ForegroundColor Cyan
            git push origin $tagName
        }

        Write-Host "Creating GitHub release..." -ForegroundColor Cyan
        
        if ($ReleaseNotesFile) {
            # Validate release notes file exists
            if (-not (Test-Path $ReleaseNotesFile)) {
                Write-Error "Release notes file not found: $ReleaseNotesFile"
                exit 1
            }
            
            gh release create $tagName --title $tagName --notes-file $ReleaseNotesFile
            Write-Host "GitHub release '$tagName' created with notes from $ReleaseNotesFile" -ForegroundColor Green
        }
        else {
            # Use auto-generated notes
            gh release create $tagName --title $tagName --generate-notes
            Write-Host "GitHub release '$tagName' created with auto-generated notes" -ForegroundColor Green
        }
    }

    Write-Host "`nSuccess! Tag '$tagName' created." -ForegroundColor Green
    if ($CreateRelease) {
        Write-Host "View release at: https://github.com/mjfusa/message-center-agent/releases/tag/$tagName" -ForegroundColor Cyan
    }
}
catch {
    Write-Error "Failed to create tag/release: $_"
    exit 1
}
