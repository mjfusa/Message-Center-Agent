<#
.SYNOPSIS
    Creates a new GitHub version tag with 'v' prefix using version from .env.production.sample.

.DESCRIPTION
    This script reads the AGENT_VERSION from env/.env.production.sample file,
    creates a new Git tag with a version number prefixed with 'v', 
    and pushes it to the remote repository.

.PARAMETER Message
    Optional tag message/annotation. If provided, creates an annotated tag.

.PARAMETER Push
    If specified, automatically pushes the tag to the remote repository.

.EXAMPLE
    .\CreateGitHubVersionTag.ps1 -Push
    Creates and pushes tag using version from .env.production.sample (e.g., "v2.0.2")

.EXAMPLE
    .\CreateGitHubVersionTag.ps1 -Message "Release version 2.0.2" -Push
    Creates an annotated tag with a message and pushes it
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Optional tag message for annotated tag")]
    [string]$Message,

    [Parameter(Mandatory = $false, HelpMessage = "Push tag to remote repository")]
    [switch]$Push
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

    Write-Host "`nSuccess! Tag '$tagName' created." -ForegroundColor Green
}
catch {
    Write-Error "Failed to create tag: $_"
    exit 1
}
