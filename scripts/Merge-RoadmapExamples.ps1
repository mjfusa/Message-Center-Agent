#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Merges examples from roadmap-openapi.json into TypeSpec-generated MessageCenterAgent.RoadmapAPI-openapi.json

.DESCRIPTION
    This script works around a TypeSpec bug where @example decorators are not emitted in the output.
    It extracts parameter examples, response examples, and x-ms-examples from the handcrafted
    roadmap-openapi.json file and merges them into the TypeSpec-generated output file.

.NOTES
    Runs automatically after TypeSpec compilation as part of the build process.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# File paths
$sourceFile = Join-Path $PSScriptRoot '..' 'appPackage' 'apiSpecificationFile' 'roadmap-openapi.json'
$targetFile = Join-Path $PSScriptRoot '..' 'appPackage' 'apiSpecificationFile' 'MessageCenterAgent.RoadmapAPI-openapi.json'

Write-Host "🔄 Merging examples into TypeSpec-generated OpenAPI file..." -ForegroundColor Cyan

# Verify source file exists
if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file not found: $sourceFile"
    exit 1
}

# Verify target file exists (should be created by TypeSpec)
if (-not (Test-Path $targetFile)) {
    Write-Warning "Target file not found: $targetFile"
    Write-Warning "TypeSpec may not have generated the RoadmapAPI output yet."
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

    # Merge parameter examples (TypeSpec generates inline parameters, not component refs)
    if ($source.components.parameters -and $target.paths.'/m365'.get.parameters) {
        Write-Host "  ➕ Merging inline parameter examples..." -ForegroundColor Gray
        
        # Map source parameter examples by parameter name
        $sourceParams = @{}
        foreach ($paramName in $source.components.parameters.PSObject.Properties.Name) {
            $sourceParam = $source.components.parameters.$paramName
            if ($sourceParam.name) {
                $sourceParams[$sourceParam.name] = $sourceParam.examples
            }
        }
        
        # Add examples to inline parameters in the operation
        $targetParams = $target.paths.'/m365'.get.parameters
        foreach ($targetParam in $targetParams) {
            if ($targetParam.name -and $sourceParams.ContainsKey($targetParam.name)) {
                $examples = $sourceParams[$targetParam.name]
                if ($examples) {
                    $targetParam | Add-Member -NotePropertyName 'examples' -NotePropertyValue $examples -Force
                    $merged += "    - $($targetParam.name) ($(($examples.PSObject.Properties.Name).Count) examples)"
                }
            }
        }
    }

    # Merge response examples
    if ($source.paths.'/m365'.get.responses.'200'.content.'application/json'.examples) {
        Write-Host "  ➕ Merging response examples..." -ForegroundColor Gray
        
        $sourceExamples = $source.paths.'/m365'.get.responses.'200'.content.'application/json'.examples
        $targetResponse = $target.paths.'/m365'.get.responses.'200'.content.'application/json'
        
        if ($targetResponse) {
            # Add examples property to response
            $targetResponse | Add-Member -NotePropertyName 'examples' -NotePropertyValue $sourceExamples -Force
            $merged += "    - Response examples ($(($sourceExamples.PSObject.Properties.Name).Count) examples)"
        }
    }

    # Merge x-ms-examples (operation-level examples)
    if ($source.'x-ms-examples') {
        Write-Host "  ➕ Merging x-ms-examples (operation examples)..." -ForegroundColor Gray
        
        # Add x-ms-examples at root level
        $target | Add-Member -NotePropertyName 'x-ms-examples' -NotePropertyValue $source.'x-ms-examples' -Force
        $merged += "    - x-ms-examples ($(($source.'x-ms-examples'.PSObject.Properties.Name).Count) examples)"
    }

    # Write merged JSON back to file with proper formatting
    Write-Host "  💾 Writing merged OpenAPI file..." -ForegroundColor Gray
    $target | ConvertTo-Json -Depth 100 | Set-Content $targetFile -Encoding UTF8

    # Report success
    Write-Host "`n✅ Successfully merged examples!" -ForegroundColor Green
    Write-Host "`nMerged content:" -ForegroundColor Cyan
    $merged | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    
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
