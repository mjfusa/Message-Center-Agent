#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Merges examples from openapi.json into TypeSpec-generated MessageCenterAgent.MessageCenterAPI-openapi.json

.DESCRIPTION
    This script works around a TypeSpec bug where @example decorators are not emitted in the output.
    It extracts parameter examples from the handcrafted openapi.json file and merges them into 
    the TypeSpec-generated Message Center API output file.

.NOTES
    Runs automatically after TypeSpec compilation as part of the build process.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# File paths
$sourceFile = Join-Path $PSScriptRoot '..' 'appPackage' 'apiSpecificationFile' 'openapi.json'
$targetFile = Join-Path $PSScriptRoot '..' 'appPackage' 'apiSpecificationFile' 'MessageCenterAgent.MessageCenterAPI-openapi.json'

Write-Host "🔄 Merging examples into TypeSpec-generated Message Center API file..." -ForegroundColor Cyan

# Verify source file exists
if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file not found: $sourceFile"
    exit 1
}

# Verify target file exists (should be created by TypeSpec)
if (-not (Test-Path $targetFile)) {
    Write-Warning "Target file not found: $targetFile"
    Write-Warning "TypeSpec may not have generated the MessageCenterAPI output yet."
    Write-Host "Skipping example merge." -ForegroundColor Yellow
    exit 0
}

try {
    # Load JSON files
    Write-Host "  📖 Reading source examples from: $sourceFile" -ForegroundColor Gray
    $source = Get-Content $sourceFile -Raw | ConvertFrom-Json -Depth 100

    Write-Host "  📖 Reading TypeSpec-generated file: $targetFile" -ForegroundColor Gray
    $target = Get-Content $targetFile -Raw | ConvertFrom-Json -Depth 100

    # Create backup
    $backupFile = "$targetFile.backup"
    Copy-Item $targetFile $backupFile -Force
    Write-Host "  💾 Backup created: $backupFile" -ForegroundColor Gray

    # Track what we're merging
    $merged = @()
    $totalExamples = 0

    # Merge parameter examples (TypeSpec generates inline parameters)
    # The source has the operation at /admin/serviceAnnouncement/messages
    $sourcePath = '/admin/serviceAnnouncement/messages'
    $targetPath = '/admin/serviceAnnouncement/messages'
    
    if ($source.paths.$sourcePath.get.parameters -and $target.paths.$targetPath.get.parameters) {
        Write-Host "  ➕ Merging inline parameter examples..." -ForegroundColor Gray
        
        # Build a map of source parameter examples by parameter name
        $sourceParams = @{}
        foreach ($sourceParam in $source.paths.$sourcePath.get.parameters) {
            if ($sourceParam.name -and $sourceParam.examples) {
                $sourceParams[$sourceParam.name] = $sourceParam.examples
            }
        }
        
        # Add examples to inline parameters in the target operation
        $targetParams = $target.paths.$targetPath.get.parameters
        foreach ($targetParam in $targetParams) {
            if ($targetParam.name -and $sourceParams.ContainsKey($targetParam.name)) {
                $examples = $sourceParams[$targetParam.name]
                if ($examples) {
                    $targetParam | Add-Member -NotePropertyName 'examples' -NotePropertyValue $examples -Force
                    $exampleCount = ($examples.PSObject.Properties.Name).Count
                    $totalExamples += $exampleCount
                    $merged += "    - $($targetParam.name) ($exampleCount examples)"
                }
            }
        }
    }

    # Write merged JSON back to file with proper formatting
    Write-Host "  💾 Writing merged OpenAPI file..." -ForegroundColor Gray
    $target | ConvertTo-Json -Depth 100 | Set-Content $targetFile -Encoding UTF8

    # Report success
    if ($merged.Count -gt 0) {
        Write-Host "`n✅ Successfully merged examples!" -ForegroundColor Green
        Write-Host "`nMerged content:" -ForegroundColor Cyan
        $merged | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        Write-Host "`n📊 Total: $totalExamples examples across $($merged.Count) parameters" -ForegroundColor Cyan
    } else {
        Write-Host "`n⚠️  No examples found to merge" -ForegroundColor Yellow
    }
    
    Write-Host "`n📄 Output file: $targetFile" -ForegroundColor Cyan
    Write-Host "💾 Backup file: $backupFile" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to merge examples: $_"
    
    # Restore from backup if it exists
    if (Test-Path $backupFile) {
        Write-Host "  🔄 Restoring from backup..." -ForegroundColor Yellow
        Copy-Item $backupFile $targetFile -Force
        Write-Host "  ✅ Restored from backup" -ForegroundColor Green
    }
    
    exit 1
}

Write-Host "`n✨ Example merge complete!" -ForegroundColor Green
