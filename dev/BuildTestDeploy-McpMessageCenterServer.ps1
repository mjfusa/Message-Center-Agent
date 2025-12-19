[CmdletBinding(SupportsShouldProcess = $true)]
param(
  # Versioning
  [Parameter(Mandatory = $false)]
  [ValidateSet('patch', 'minor', 'major', 'none')]
  [string] $BumpVersion = 'patch',

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
  # If not provided, the script will try to acquire one via mcp-message-center-server/scripts/GetMcpAccessToken.ps1.
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
  [int] $HealthTimeoutSeconds = 180
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

  $serverDir = Join-Path $RepoRoot 'mcp-message-center-server'

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
        $tokenScript = Join-Path $RepoRoot 'mcp-message-center-server\scripts\GetMcpAccessToken.ps1'
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
$packageJsonPath = Join-Path $repoRoot 'mcp-message-center-server\package.json'

if (-not (Test-Path -LiteralPath $packageJsonPath)) {
  throw "Expected file not found: $packageJsonPath"
}

Write-Section 'Version + tag'

# Optionally bump/set npm version
if ($BumpVersion -ne 'none' -or $Version) {
  Push-Location (Join-Path $repoRoot 'mcp-message-center-server')
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
$imageTag = "mcp-message-center-server:$Tag"
$imageRef = "$loginServer/$imageTag"

Write-Host "ACR login server: $loginServer"
Write-Host "Image ref:        $imageRef"

if (-not $SkipAcrBuild) {
  Write-Section 'Build + push image (ACR build)'

  if ($PSCmdlet.ShouldProcess($AcrName, "az acr build -t $imageTag")) {
    Push-Location $repoRoot
    try {
      # Uses ACR build so Docker is not required locally.
      $null = Invoke-Az @(
        'acr', 'build',
        '-r', $AcrName,
        '-t', $imageTag,
        '-f', 'mcp-message-center-server/Dockerfile',
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
} else {
  Write-Section 'Deploy to Azure Container Apps'
  Write-Host 'Skipping deploy (-SkipDeploy).'
}

Write-Section 'Summary'
Write-Host "Version:  $currentVersion"
Write-Host "Image:    $imageRef"
Write-Host 'Done.'
