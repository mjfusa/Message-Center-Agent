param(
  [string]$EnvFile = ""
)

$ErrorActionPreference = 'Stop'

if (-not $EnvFile -or $EnvFile.Trim() -eq '') {
  $EnvFile = Join-Path $PSScriptRoot "..\.env.local"
}

$resolved = Resolve-Path -LiteralPath $EnvFile
Write-Host "Loading env vars from: $resolved"

Get-Content -LiteralPath $resolved | ForEach-Object {
  $line = $_
  if (-not $line) { return }
  $trimmed = $line.Trim()
  if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { return }

  $parts = $trimmed.Split('=', 2)
  if ($parts.Length -ne 2) { return }

  $name = $parts[0].Trim()
  $value = $parts[1]

  if ($name -eq '') { return }

  [Environment]::SetEnvironmentVariable($name, $value)
}

Write-Host "Loaded GRAPH_TENANT_ID=$env:GRAPH_TENANT_ID"
