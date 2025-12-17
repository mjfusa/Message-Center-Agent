[CmdletBinding()]
param(
  # Tenant used for interactive login if needed.
  [string]$TenantId = $env:GRAPH_TENANT_ID,

  # The Entra app (client) ID of the MCP API resource.
  # Default: GRAPH_CLIENT_ID (same app registration the server uses).
  [string]$ApiClientId = $env:GRAPH_CLIENT_ID,

  # Scope name exposed by the MCP API app registration.
  [string]$ScopeName = 'access_as_user',

  # If set, runs an interactive az login with the requested scope (useful for first-time consent).
  [switch]$Login,

  # If set, prints a small JSON payload (token + metadata) instead of only the token.
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Import-DotEnv([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('#')) { continue }
    $idx = $trimmed.IndexOf('=')
    if ($idx -lt 1) { continue }

    $key = $trimmed.Substring(0, $idx).Trim()
    $val = $trimmed.Substring($idx + 1).Trim()

    # Strip surrounding quotes
    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
      $val = $val.Substring(1, $val.Length - 2)
    }

    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $existing = (Get-Item -Path "env:$key" -ErrorAction SilentlyContinue).Value
      if ([string]::IsNullOrWhiteSpace($existing)) {
        Set-Item -Path "env:$key" -Value $val
      }
    }
  }
}

# Convenience: load env vars from ../.env.local (gitignored) when present.
Import-DotEnv (Join-Path $PSScriptRoot '..\.env.local')

# Parameter default values are evaluated before Import-DotEnv runs.
# Backfill values from env after loading .env.local.
if ([string]::IsNullOrWhiteSpace($TenantId)) {
  $TenantId = $env:GRAPH_TENANT_ID
}

if ([string]::IsNullOrWhiteSpace($ApiClientId)) {
  $ApiClientId = $env:GRAPH_CLIENT_ID
}

function Require([string]$name, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required value: $name"
  }
  return $value
}

$ApiClientId = Require 'ApiClientId (or GRAPH_CLIENT_ID env var)' $ApiClientId

$scope = "api://$ApiClientId/$ScopeName"

function Invoke-Az([string[]]$AzArgs) {
  $output = & az @AzArgs 2>&1
  $exit = $LASTEXITCODE

  # IMPORTANT: Do not use Out-String here. It wraps long lines (like JWTs) to console width,
  # which corrupts tokens and breaks JSON parsing.
  $text = ''
  if ($null -ne $output) {
    if ($output -is [System.Array]) {
      $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    } else {
      $text = [string]$output
    }
  }

  return [pscustomobject]@{ ExitCode = $exit; Output = $text.Trim() }
}

if ($Login) {
  if ([string]::IsNullOrWhiteSpace($TenantId)) {
    throw 'TenantId is required when using -Login (or set GRAPH_TENANT_ID env var).'
  }

  # Force an interactive login that requests consent for the MCP API scope.

  $null = Invoke-Az @('logout')

  $login = Invoke-Az @('login', '--tenant', $TenantId, '--scope', $scope)
  if ($login.ExitCode -ne 0) {
    throw "az login failed: $($login.Output)"
  }
}

${tokenResult} = Invoke-Az @(
  'account',
  'get-access-token',
  '--scope',
  $scope,
  '--query',
  'accessToken',
  '--output',
  'tsv',
  '--only-show-errors'
)

if (${tokenResult}.ExitCode -ne 0) {
  $msg = ${tokenResult}.Output

  if ($msg -match 'AADSTS65001' -or $msg -match 'consent_required') {
    $hint = @(
      'Consent is required for Azure CLI to request this scope.',
      "Run:",
      "  az logout",
      "  az login --tenant `"$TenantId`" --scope `"$scope`"",
      'Then re-run this script.'
    ) -join [Environment]::NewLine

    throw ($msg + [Environment]::NewLine + [Environment]::NewLine + $hint)
  }

  throw "Failed to get access token: $msg"
}

$raw = ${tokenResult}.Output
$lines = $raw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$accessToken = $lines | Select-Object -Last 1

# Azure CLI can print a first-run banner to stdout which would otherwise get mixed into our capture.
# Since we query only `accessToken` as TSV, the token should be the last non-empty line.
$looksLikeJwt = $accessToken -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$'
if (-not $looksLikeJwt) {
  throw "Azure CLI returned unexpected output (not a JWT). Try re-running, or use -Verbose to inspect output. Raw output:`n$raw"
}

if ($AsJson) {
  $out = [pscustomobject]@{
    scope = $scope
    accessToken = $accessToken
  }
  $out | ConvertTo-Json -Depth 5
} else {
  # Print only the token so callers can easily paste/pipe it.
  $accessToken
}
