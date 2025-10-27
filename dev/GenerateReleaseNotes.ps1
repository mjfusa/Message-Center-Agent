#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates release notes from git commits in the local repository.

.DESCRIPTION
    This script analyzes the git log from the local repository to generate
    a formatted release notes document for commits made in the last N days.

.PARAMETER Days
    Number of days to look back for commits (default: 1)

.PARAMETER OutputFile
    Path to the output file for release notes (default: RELEASE_NOTES.md)

.PARAMETER Branch
    Git branch to analyze (default: main)

.EXAMPLE
    .\GenerateReleaseNotes.ps1
    Generates release notes for commits in the last day on main branch

.EXAMPLE
    .\GenerateReleaseNotes.ps1 -Days 7 -OutputFile WEEKLY_RELEASE_NOTES.md
    Generates release notes for the last 7 days
#>

param(
    [int]$Days = 1,
    [string]$OutputFile = "RELEASE_NOTES.md",
    [string]$Branch = "main"
)

# Function to check if we're in a git repository
function Test-GitRepository {
    try {
        $null = git rev-parse --git-dir 2>&1
        return $true
    }
    catch {
        Write-Error "Not in a git repository. Please run this script from within the repository."
        return $false
    }
}

# Function to fetch commits from the last N days
function Get-RecentCommits {
    param(
        [string]$Branch,
        [int]$Days
    )

    $sinceDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-dd")
    
    Write-Host "Fetching commits from '$Branch' since $sinceDate..." -ForegroundColor Cyan
    
    try {
        # Get commits with detailed information
        $gitLog = git log $Branch --since="$Days days ago" --pretty=format:"%H|%h|%an|%ae|%ai|%s" --no-merges 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitLog)) {
            Write-Warning "No commits found in the last $Days day(s) on branch '$Branch'."
            return @()
        }
        
        $commits = @()
        foreach ($line in $gitLog -split "`n") {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            
            $parts = $line -split "\|", 6
            if ($parts.Count -eq 6) {
                $commits += @{
                    FullSha = $parts[0]
                    ShortSha = $parts[1]
                    Author = $parts[2]
                    Email = $parts[3]
                    Date = $parts[4]
                    Message = $parts[5]
                }
            }
        }
        
        return $commits
    }
    catch {
        Write-Error "Failed to fetch commits: $_"
        return @()
    }
}

# Function to get file changes for a commit
function Get-CommitStats {
    param([string]$CommitSha)
    
    try {
        $stats = git show --stat --pretty="" $CommitSha | Select-Object -Last 1
        return $stats
    }
    catch {
        return ""
    }
}

# Function to categorize commit based on message
function Get-CommitCategory {
    param([string]$Message)
    
    $messageLower = $Message.ToLower()
    
    if ($messageLower -match "^feat(\(.*\))?:|^feature:") { return "✨ Features" }
    if ($messageLower -match "^fix(\(.*\))?:|^bugfix:") { return "🐛 Bug Fixes" }
    if ($messageLower -match "^docs(\(.*\))?:|^documentation:") { return "📚 Documentation" }
    if ($messageLower -match "^style(\(.*\))?:") { return "💎 Style" }
    if ($messageLower -match "^refactor(\(.*\))?:") { return "♻️ Refactoring" }
    if ($messageLower -match "^perf(\(.*\))?:|^performance:") { return "⚡ Performance" }
    if ($messageLower -match "^test(\(.*\))?:") { return "✅ Tests" }
    if ($messageLower -match "^build(\(.*\))?:") { return "🔨 Build" }
    if ($messageLower -match "^ci(\(.*\))?:") { return "👷 CI/CD" }
    if ($messageLower -match "^chore(\(.*\))?:") { return "🔧 Chore" }
    if ($messageLower -match "clean.*up|cleanup") { return "🧹 Cleanup" }
    if ($messageLower -match "update|bump|version") { return "📦 Updates" }
    if ($messageLower -match "merge") { return "🔀 Merges" }
    
    return "📝 Other Changes"
}

# Function to generate release notes
function New-ReleaseNotes {
    param(
        [array]$Commits,
        [string]$OutputFile,
        [int]$Days,
        [string]$Branch
    )
    
    if ($Commits.Count -eq 0) {
        Write-Warning "No commits found in the last $Days day(s)."
        
        # Create a minimal release notes file
        $content = @()
        $content += "# Release Notes"
        $content += ""
        $content += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
        $content += "**Period:** Last $Days day(s)"
        $content += "**Branch:** $Branch"
        $content += ""
        $content += "No commits found in the specified time period."
        $content += ""
        $content += "---"
        $content += ""
        $content += "*This release notes document was automatically generated from git commits.*"
        
        $content | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "Empty release notes file created: $OutputFile" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Generating release notes with $($Commits.Count) commit(s)..." -ForegroundColor Cyan
    
    # Group commits by category
    $categorizedCommits = @{}
    
    foreach ($commit in $Commits) {
        $message = $commit.Message
        $category = Get-CommitCategory -Message $message
        
        if (-not $categorizedCommits.ContainsKey($category)) {
            $categorizedCommits[$category] = @()
        }
        
        # Get commit stats
        $stats = Get-CommitStats -CommitSha $commit.FullSha
        
        $categorizedCommits[$category] += @{
            Sha = $commit.ShortSha
            Message = $message
            Author = $commit.Author
            Date = $commit.Date
            Stats = $stats
        }
    }
    
    # Generate markdown content
    $content = @()
    $content += "# Release Notes"
    $content += ""
    $content += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    $content += "**Period:** Last $Days day(s)"
    $content += "**Branch:** $Branch"
    $content += "**Total Commits:** $($Commits.Count)"
    $content += ""
    
    # Get repository remote URL for linking
    $remoteUrl = ""
    try {
        $remote = git config --get remote.origin.url
        if ($remote -match "github.com[:/](.+/.+?)(\.git)?$") {
            $repoPath = $Matches[1] -replace "\.git$", ""
            $remoteUrl = "https://github.com/$repoPath"
        }
    }
    catch {
        # Ignore if we can't get the remote URL
    }
    
    # Sort categories for better presentation
    $categoryOrder = @(
        "✨ Features",
        "🐛 Bug Fixes",
        "📚 Documentation",
        "⚡ Performance",
        "♻️ Refactoring",
        "🧹 Cleanup",
        "📦 Updates",
        "🔀 Merges",
        "🔨 Build",
        "👷 CI/CD",
        "✅ Tests",
        "💎 Style",
        "🔧 Chore",
        "📝 Other Changes"
    )
    
    foreach ($category in $categoryOrder) {
        if ($categorizedCommits.ContainsKey($category)) {
            $content += "## $category"
            $content += ""
            
            foreach ($commit in $categorizedCommits[$category]) {
                if ($remoteUrl) {
                    $content += "- **[$($commit.Sha)]($remoteUrl/commit/$($commit.Sha))** $($commit.Message)"
                } else {
                    $content += "- **$($commit.Sha)** $($commit.Message)"
                }
                $content += "  - *Author:* $($commit.Author)"
                $content += "  - *Date:* $($commit.Date)"
                if ($commit.Stats) {
                    $content += "  - *Changes:* $($commit.Stats.Trim())"
                }
                $content += ""
            }
        }
    }
    
    # Add footer
    $content += "---"
    $content += ""
    $content += "*This release notes document was automatically generated from git commits.*"
    
    # Write to file
    $content | Out-File -FilePath $OutputFile -Encoding UTF8
    
    Write-Host "Release notes generated successfully: $OutputFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Preview:" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    $content | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
    if ($content.Count -gt 30) {
        Write-Host "... (truncated, see $OutputFile for full content)" -ForegroundColor Gray
    }
    Write-Host "========================================" -ForegroundColor Yellow
}

# Main execution
Write-Host ""
Write-Host "Release Notes Generator" -ForegroundColor Magenta
Write-Host "======================" -ForegroundColor Magenta
Write-Host ""

if (-not (Test-GitRepository)) {
    exit 1
}

$commits = Get-RecentCommits -Branch $Branch -Days $Days

New-ReleaseNotes -Commits $commits -OutputFile $OutputFile -Days $Days -Branch $Branch

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
