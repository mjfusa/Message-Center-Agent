[CmdletBinding()]
param(
  # Azure settings
  [Parameter(Mandatory = $false)]
  [string] $ResourceGroupName = 'rg-mcp-messages-roadmap',

  [Parameter(Mandatory = $false)]
  [string] $Location = 'westus',

  # ACR name must be globally unique, 5-50 chars, lowercase letters/numbers only.
  [Parameter(Mandatory = $true)]
  [string] $AcrName,

  # Image tags
  [Parameter(Mandatory = $false)]
  [string] $MessageCenterTag = '0.1.0',

  [Parameter(Mandatory = $false)]
  [string] $RoadmapTag = '0.1.0',

  # Optional: update infra/main.parameters.json with the image references.
  [Parameter(Mandatory = $false)]
  [switch] $UpdateParameters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Az {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Args
  )

  & az @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed (exit $LASTEXITCODE): az $($Args -join ' ')"
  }
}

function Normalize-AcrName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  $lower = $Name.ToLowerInvariant()
  if ($lower -ne $Name) {
    Write-Host "Normalizing ACR name to lowercase: '$Name' -> '$lower'"
  }

  if ($lower -notmatch '^[a-z0-9]{5,50}$') {
    throw "Invalid ACR name '$Name'. ACR names must be 5-50 chars, lowercase letters/numbers only. Example: 'acrmcpmessagesroadmapwu'."
  }

  return $lower
}

function Assert-AzInstalled {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) not found. Install it first: https://learn.microsoft.com/cli/azure/install-azure-cli'
  }
}

function Get-RepoRoot {
  # This script lives in infra/, so repo root is parent of this file's folder.
  $here = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $here '..')).Path
}

function Ensure-AzLogin {
  try {
    Invoke-Az -Args @('account', 'show', '--only-show-errors') | Out-Null
  } catch {
    throw 'Not logged into Azure CLI. Run: az login'
  }
}

function Ensure-ResourceGroup {
  param(
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] [string] $Loc
  )

  $exists = Invoke-Az -Args @('group', 'exists', '-n', $Name, '--only-show-errors') | ConvertFrom-Json
  if (-not $exists) {
    Write-Host "Creating resource group '$Name' in '$Loc'..."
    Invoke-Az -Args @('group', 'create', '-n', $Name, '-l', $Loc, '--only-show-errors') | Out-Null
  } else {
    Write-Host "Resource group '$Name' already exists."
  }
}

function Ensure-Acr {
  param(
    [Parameter(Mandatory = $true)] [string] $Name,
    [Parameter(Mandatory = $true)] [string] $Rg,
    [Parameter(Mandatory = $true)] [string] $Loc
  )

  $acr = $null
  try {
    $acr = Invoke-Az -Args @('acr', 'show', '-n', $Name, '-g', $Rg, '--only-show-errors') | ConvertFrom-Json
  } catch {
    $acr = $null
  }

  if ($null -eq $acr) {
    Write-Host "Creating ACR '$Name' (Basic) in '$Rg' / '$Loc'..."
    Invoke-Az -Args @('acr', 'create', '-g', $Rg, '-n', $Name, '-l', $Loc, '--sku', 'Basic', '--only-show-errors') | Out-Null
  } else {
    Write-Host "ACR '$Name' already exists."
  }

  # NOTE: We intentionally do NOT call `az acr login` here because it shells out to Docker.
  # `az acr build` does not require Docker to be installed locally.
  Write-Host "Validating ACR access for '$Name' (no Docker required)..."
  Invoke-Az -Args @('acr', 'show', '-n', $Name, '-g', $Rg, '--query', 'loginServer', '-o', 'tsv', '--only-show-errors') | Out-Null
}

function Build-AcrImage {
  param(
    [Parameter(Mandatory = $true)] [string] $Acr,
    [Parameter(Mandatory = $true)] [string] $Dockerfile,
    [Parameter(Mandatory = $true)] [string] $Tag,
    [Parameter(Mandatory = $true)] [string] $ContextPath
  )

  Write-Host "Building and pushing '$Tag' using Dockerfile '$Dockerfile'..."
  Invoke-Az -Args @('acr', 'build', '-r', $Acr, '-t', $Tag, '-f', $Dockerfile, $ContextPath, '--only-show-errors') | Out-Host
}

function Update-ParametersFile {
  param(
    [Parameter(Mandatory = $true)] [string] $ParametersPath,
    [Parameter(Mandatory = $true)] [string] $MessageCenterImage,
    [Parameter(Mandatory = $true)] [string] $RoadmapImage
  )

  if (-not (Test-Path $ParametersPath)) {
    throw "Parameters file not found: $ParametersPath"
  }

  $json = Get-Content -Raw -Path $ParametersPath | ConvertFrom-Json

  if ($null -eq $json.parameters) {
    throw "Unexpected parameters file format (missing 'parameters'): $ParametersPath"
  }

  if ($null -eq $json.parameters.messageCenterImage) {
    throw "Missing parameter 'messageCenterImage' in: $ParametersPath"
  }

  if ($null -eq $json.parameters.roadmapImage) {
    throw "Missing parameter 'roadmapImage' in: $ParametersPath"
  }

  $json.parameters.messageCenterImage.value = $MessageCenterImage
  $json.parameters.roadmapImage.value = $RoadmapImage

  $json | ConvertTo-Json -Depth 20 | Set-Content -Path $ParametersPath -Encoding UTF8
  Write-Host "Updated: $ParametersPath"
}

Assert-AzInstalled
Ensure-AzLogin

$AcrName = Normalize-AcrName -Name $AcrName

$repoRoot = Get-RepoRoot
Write-Host "Repo root: $repoRoot"

Ensure-ResourceGroup -Name $ResourceGroupName -Loc $Location
Ensure-Acr -Name $AcrName -Rg $ResourceGroupName -Loc $Location

$loginServer = (Invoke-Az -Args @('acr', 'show', '-n', $AcrName, '-g', $ResourceGroupName, '--query', 'loginServer', '-o', 'tsv', '--only-show-errors')).Trim()

Push-Location $repoRoot
try {
  $messageCenterImageTag = "mcp-message-center-server:$MessageCenterTag"
  $roadmapImageTag = "mcp-roadmap-server:$RoadmapTag"

  Build-AcrImage -Acr $AcrName -Dockerfile 'mcp-message-center-server/Dockerfile' -Tag $messageCenterImageTag -ContextPath '.'
  Build-AcrImage -Acr $AcrName -Dockerfile 'mcp-roadmap-server/Dockerfile' -Tag $roadmapImageTag -ContextPath '.'

  $messageCenterImageRef = "$loginServer/$messageCenterImageTag"
  $roadmapImageRef = "$loginServer/$roadmapImageTag"

  Write-Host ''
  Write-Host 'Image references (copy into infra/main.parameters.json):'
  Write-Host "  messageCenterImage = $messageCenterImageRef"
  Write-Host "  roadmapImage       = $roadmapImageRef"

  if ($UpdateParameters) {
    $paramsPath = Join-Path $repoRoot 'infra/main.parameters.json'
    Update-ParametersFile -ParametersPath $paramsPath -MessageCenterImage $messageCenterImageRef -RoadmapImage $roadmapImageRef
  }

  Write-Host ''
  Write-Host 'Optional sanity checks:'
  Write-Host "  az acr repository show-tags -n $AcrName --repository mcp-message-center-server -o table"
  Write-Host "  az acr repository show-tags -n $AcrName --repository mcp-roadmap-server -o table"
} finally {
  Pop-Location
}
