<#[
.SYNOPSIS
Builds, publishes (ACR), and deploys the Message Center MCP server to Azure Container Apps.

.DESCRIPTION
This script can:
- Optionally bump/set the npm package version (without creating git tags)
- Optionally run a local build + smoke test (starts the server and checks /healthz; can also run MCP smoke if a token is available)
- Build + push the container image using Azure Container Registry remote build ("az acr build")
- Deploy the new image to an Azure Container App
- Optionally wait for https://<fqdn>/healthz and/or validate POST /mcp via a tools/list call

Monorepo note:
The Dockerfile uses monorepo-relative COPY paths (e.g. "COPY mcp-message-center-server/src ./src").
When running in the monorepo, this script automatically uses the monorepo root as the ACR build context
and passes -f "mcp-message-center-server/Dockerfile".

.PARAMETER AcrName
Azure Container Registry resource name (not login server). Example: acrmcpmessagesroadmap

.PARAMETER ResourceGroupName
Azure resource group containing the ACR and the Container App.

.PARAMETER ContainerAppName
Azure Container App name to update.

.PARAMETER SkipLocalTest
Skips local build/smoke (useful for CI or when you only want ACR build + deploy).

.PARAMETER WaitForHealth
After deploy, polls https://<fqdn>/healthz until 200 or timeout.

.PARAMETER TestMcp
After deploy, POSTs a JSON-RPC tools/list request to https://<fqdn>/mcp.

.PARAMETER WhatIf
Shows what would happen without actually running ACR build or deploy.

.EXAMPLE
# Safe local-only validation (no Azure calls):
pwsh -NoProfile -File .\mcp-message-center-server\dev\BuildTestDeploy.ps1 -AcrName acrmcpmessagesroadmap -SkipLocalTest -SkipAcrBuild -SkipDeploy

.EXAMPLE
# ACR build + deploy, then wait for health and validate /mcp:
pwsh -NoProfile -File .\mcp-message-center-server\dev\BuildTestDeploy.ps1 -AcrName acrmcpmessagesroadmap -WaitForHealth -TestMcp

.EXAMPLE
# Preview actions (no ACR build / deploy), still computes tag:
pwsh -NoProfile -File .\mcp-message-center-server\dev\BuildTestDeploy.ps1 -AcrName acrmcpmessagesroadmap -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  # Versioning
  [Parameter(Mandatory = $false)]
  [ValidateSet('patch', 'minor', 'major', 'none')]
  [string] $BumpVersion = 'none',

  [Parameter(Mandatory = $false)]
  [string] $Version,

  # Image tag override. If not provided, computed from version + git SHA.
  [Parameter(Mandatory = $false)]
  [string] $Tag,

  # Azure settings
  [Parameter(Mandatory = $false)]
  [string] $SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string] $ResourceGroupName = 'rg-mcp-messages-roadmap',

  [Parameter(Mandatory = $false)]
  [string] $ContainerAppName = 'mcagent-mcp-mc',

  # ACR name (not login server). Example: acrmcpmessagesroadmapwu
  [Parameter(Mandatory = $true)]
  [string] $AcrName,

  # Local build/test settings
  [Parameter(Mandatory = $false)]
  [int] $LocalPort = 8080,

  # Optional: bearer token for local smoke test (api://<clientId>/access_as_user).
  # If not provided, the script will try to acquire one via scripts/GetMcpAccessToken.ps1.
  [Parameter(Mandatory = $false)]
  [string] $McpAccessToken,

  [Parameter(Mandatory = $false)]
  [switch] $SkipLocalTest,

  [Parameter(Mandatory = $false)]
  [switch] $SkipAcrBuild,

  [Parameter(Mandatory = $false)]
  [switch] $SkipDeploy,

  # Optional: after deploy, poll https://<fqdn>/healthz until it returns 200
  [Parameter(Mandatory = $false)]
  [switch] $WaitForHealth,

  [Parameter(Mandatory = $false)]
  [int] $HealthTimeoutSeconds = 180,

  # Optional: after deploy, POST /mcp with a tools/list request to validate the MCP endpoint is reachable.
  [Parameter(Mandatory = $false)]
  [switch] $TestMcp,

  [Parameter(Mandatory = $false)]
  [int] $McpTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command([string]$Name, [string]$Hint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command '$Name'. $Hint"
  }
}

function Invoke-Az([string[]]$AzArgs) {
  $output = & az @AzArgs 2>&1
  $exit = $LASTEXITCODE

  # Do NOT use Out-String here; it wraps long lines and can corrupt tokens/values.
  $text = ''
  if ($null -ne $output) {
    if ($output -is [System.Array]) {
      $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    } else {
      $text = [string]$output
    }
  }

  if ($exit -ne 0) {
    throw "Azure CLI command failed (exit $exit): az $($AzArgs -join ' ')`n$text"
  }

  return $text.Trim()
}

function Get-RepoRoot {
  $here = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $here '..')).Path
}

function Get-BuildContext([string]$ServerRoot) {
  # The Dockerfile currently expects monorepo-relative COPY paths like:
  #   COPY mcp-message-center-server/src ./src
  # So for the monorepo, the build context must be the monorepo root and -f must be the server Dockerfile path.
  $serverName = Split-Path -Leaf $ServerRoot
  $monorepoRoot = (Resolve-Path (Join-Path $ServerRoot '..')).Path

  $monorepoDockerfile = Join-Path $monorepoRoot "$serverName\Dockerfile"
  if (Test-Path -LiteralPath $monorepoDockerfile) {
    return [pscustomobject]@{
      ContextDir = $monorepoRoot
      DockerfileRelativePath = "$serverName/Dockerfile"
    }
  }

  # Fallback: standalone repo layout (context is server root)
  $standaloneDockerfile = Join-Path $ServerRoot 'Dockerfile'
  if (Test-Path -LiteralPath $standaloneDockerfile) {
    return [pscustomobject]@{
      ContextDir = $ServerRoot
      DockerfileRelativePath = 'Dockerfile'
    }
  }

  throw "Could not find a Dockerfile for build context. Expected either '$monorepoDockerfile' or '$standaloneDockerfile'."
}

function ConvertTo-DockerTag([string]$Value) {
  # Docker tags must match: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}
  $v = $Value.Trim()
  $v = $v -replace '[^A-Za-z0-9_.-]', '-'
  $v = $v.Trim('-')
  if ([string]::IsNullOrWhiteSpace($v)) {
    throw "Computed image tag is empty."
  }
  if ($v.Length -gt 128) {
    $v = $v.Substring(0, 128)
  }
  return $v
}

function Get-GitShortSha([string]$RepoRoot) {
  try {
    $sha = & git -C $RepoRoot rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { return ($sha | ForEach-Object { [string]$_ }).Trim() }
  } catch { }
  return "nogit"
}

function Read-PackageJsonVersion([string]$PackageJsonPath) {
  $pkg = Get-Content -Raw -LiteralPath $PackageJsonPath | ConvertFrom-Json
  return [string]$pkg.version
}

function Write-Section([string]$Title) {
  Write-Host ''
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Start-LocalServerAndSmoke([string]$RepoRoot, [int]$Port) {
  Write-Section "Local build + smoke"

  $serverDir = $RepoRoot

  Push-Location $serverDir
  try {
    Write-Host 'Installing deps (npm ci)...'
    & npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
      Write-Host ''
      Write-Host 'npm ci failed.' -ForegroundColor Red
      Write-Host 'Common causes on Windows:'
      Write-Host '- A running node process is locking files under node_modules'
      Write-Host '- Antivirus/Defender is scanning and holding locks'
      Write-Host 'Fix: stop node processes, close any watchers/terminals using the folder, then retry; or re-run with -SkipLocalTest.'
      throw 'npm ci failed'
    }

    Write-Host 'Building (npm run build)...'
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw 'npm run build failed' }

    $env:PORT = [string]$Port

    # Start server in background
    Write-Host "Starting server on port $Port..."
    $proc = Start-Process -FilePath 'node' -ArgumentList @('--enable-source-maps', 'dist/server.js') -PassThru -NoNewWindow

    try {
      $deadline = (Get-Date).AddSeconds(30)
      $healthUrl = "http://localhost:$Port/healthz"
      do {
        Start-Sleep -Milliseconds 500
        try {
          $resp = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 5 -SkipHttpErrorCheck
          if ($resp.StatusCode -eq 200) { break }
        } catch {
          # ignore until deadline
        }
      } while ((Get-Date) -lt $deadline)

      $env:MCP_URL = "http://localhost:$Port/mcp"

      $token = $script:McpAccessToken

      if (-not $token) {
        # Best-effort: try to acquire a token using the existing helper script.
        # This requires az login + GRAPH_CLIENT_ID in env/.env.local.
        $tokenScript = Join-Path $RepoRoot 'scripts\GetMcpAccessToken.ps1'
        if (Test-Path -LiteralPath $tokenScript) {
          try {
            & az account show --only-show-errors | Out-Null
            if ($LASTEXITCODE -eq 0) {
              $token = (& pwsh -NoProfile -File $tokenScript) | Select-Object -Last 1
            }
          } catch {
            # ignore
          }
        }
      }

      if (-not $token) {
        Write-Host 'Skipping MCP smoke: no access token available.' -ForegroundColor Yellow
        Write-Host 'Provide -McpAccessToken, or set GRAPH_CLIENT_ID and run `az login` so the script can acquire one.'
        return
      }

      Write-Host 'Running smoke (npm run smoke)...'
      $env:MCP_ACCESS_TOKEN = [string]$token
      & npm run smoke
      if ($LASTEXITCODE -ne 0) { throw 'npm run smoke failed' }

      Write-Host 'Local smoke succeeded.' -ForegroundColor Green
    } finally {
      if ($proc -and -not $proc.HasExited) {
        Write-Host 'Stopping local server...'
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      }
    }
  } finally {
    Pop-Location
  }
}

Assert-Command 'npm' 'Install Node.js (>= 20) and npm.'
Assert-Command 'az' 'Install Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli'

$repoRoot = Get-RepoRoot
$packageJsonPath = Join-Path $repoRoot 'package.json'

if (-not (Test-Path -LiteralPath $packageJsonPath)) {
  throw "Expected file not found: $packageJsonPath"
}

Write-Section 'Version + tag'

# Optionally bump/set npm version
if ($BumpVersion -ne 'none' -or $Version) {
  Push-Location $repoRoot
  try {
    if ($Version) {
      Write-Host "Setting npm package version to $Version (no git tag)..."
      & npm version $Version --no-git-tag-version
      if ($LASTEXITCODE -ne 0) { throw 'npm version failed' }
    } elseif ($BumpVersion -ne 'none') {
      Write-Host "Bumping npm package version ($BumpVersion) (no git tag)..."
      & npm version $BumpVersion --no-git-tag-version
      if ($LASTEXITCODE -ne 0) { throw 'npm version failed' }
    }
  } finally {
    Pop-Location
  }
}

$currentVersion = Read-PackageJsonVersion -PackageJsonPath $packageJsonPath
$gitSha = Get-GitShortSha -RepoRoot $repoRoot

if (-not $Tag) {
  $Tag = ConvertTo-DockerTag -Value "$currentVersion-$gitSha"
} else {
  $Tag = ConvertTo-DockerTag -Value $Tag
}

Write-Host "Package version: $currentVersion"
Write-Host "Image tag:       $Tag"

if (-not $SkipLocalTest) {
  Start-LocalServerAndSmoke -RepoRoot $repoRoot -Port $LocalPort
} else {
  Write-Section 'Local build + smoke'
  Write-Host 'Skipping local test (-SkipLocalTest).'
}

$imageTag = "mcp-message-center-server:$Tag"
$imageRef = $null

if (-not $SkipAcrBuild -or -not $SkipDeploy) {
  Write-Section 'Azure login'

  # Ensure az login
  try {
    $null = Invoke-Az @('account', 'show', '--only-show-errors')
  } catch {
    throw 'Not logged into Azure CLI. Run: az login'
  }

  if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId"
    $null = Invoke-Az @('account', 'set', '--subscription', $SubscriptionId, '--only-show-errors')
  }

  $rawLoginServer = Invoke-Az @('acr', 'show', '-n', $AcrName, '-g', $ResourceGroupName, '--query', 'loginServer', '-o', 'tsv', '--only-show-errors')
  $loginServer = ($rawLoginServer -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1).Trim()
  $imageRef = "$loginServer/$imageTag"

  Write-Host "ACR login server: $loginServer"
  Write-Host "Image ref:        $imageRef"
} else {
  Write-Section 'Azure login'
  Write-Host 'Skipping Azure/ACR lookup (-SkipAcrBuild and -SkipDeploy).'
  $imageRef = "<skipped>/$imageTag"
}

if (-not $SkipAcrBuild) {
  Write-Section 'Build + push image (ACR build)'

  if ($PSCmdlet.ShouldProcess($AcrName, "az acr build -t $imageTag")) {
    $build = Get-BuildContext -ServerRoot $repoRoot
    Push-Location $build.ContextDir
    try {
      # Uses ACR build so Docker is not required locally.
      $null = Invoke-Az @(
        'acr', 'build',
        '-r', $AcrName,
        '-t', $imageTag,
        '-f', $build.DockerfileRelativePath,
        '.',
        '--only-show-errors'
      )
    } finally {
      Pop-Location
    }
  }
} else {
  Write-Section 'Build + push image (ACR build)'
  Write-Host 'Skipping ACR build (-SkipAcrBuild).'
}

if (-not $SkipDeploy) {
  Write-Section 'Deploy to Azure Container Apps'

  if ($PSCmdlet.ShouldProcess($ContainerAppName, "az containerapp update --image $imageRef")) {
    $null = Invoke-Az @(
      'containerapp', 'update',
      '-g', $ResourceGroupName,
      '-n', $ContainerAppName,
      '--image', $imageRef,
      '--only-show-errors'
    )
  }

  $rawFqdn = Invoke-Az @('containerapp', 'show', '-g', $ResourceGroupName, '-n', $ContainerAppName, '--query', 'properties.configuration.ingress.fqdn', '-o', 'tsv', '--only-show-errors')
  $fqdn = ($rawFqdn -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1).Trim()
  if ($fqdn) {
    Write-Host "FQDN: https://$fqdn" -ForegroundColor Green
  }

  if ($WaitForHealth -and $fqdn) {
    Write-Host "Waiting for health: https://$fqdn/healthz (timeout ${HealthTimeoutSeconds}s)"
    $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
    do {
      try {
        $resp = Invoke-WebRequest -Uri "https://$fqdn/healthz" -Method GET -TimeoutSec 10 -SkipHttpErrorCheck
        if ($resp.StatusCode -eq 200) {
          Write-Host 'Health check OK.' -ForegroundColor Green
          break
        }
      } catch {
        # ignore and retry
      }

      Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    if ((Get-Date) -ge $deadline) {
      throw "Timed out waiting for https://$fqdn/healthz"
    }
  }

  if ($TestMcp -and $fqdn) {
    Write-Host "Testing MCP endpoint: https://$fqdn/mcp (tools/list)" -ForegroundColor Cyan
    $body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} } | ConvertTo-Json -Depth 10
    $resp = Invoke-WebRequest -Method Post -Uri "https://$fqdn/mcp" -ContentType 'application/json' -Headers @{ Accept = 'application/json, text/event-stream' } -Body $body -TimeoutSec $McpTimeoutSeconds -SkipHttpErrorCheck
    if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
      throw "MCP test failed ($($resp.StatusCode)): $([string]$resp.Content)"
    }
    Write-Host 'MCP endpoint OK.' -ForegroundColor Green
  }
} else {
  Write-Section 'Deploy to Azure Container Apps'
  Write-Host 'Skipping deploy (-SkipDeploy).'
}

Write-Section 'Summary'
Write-Host "Version:  $currentVersion"
Write-Host "Image:    $imageRef"
Write-Host 'Done.'
