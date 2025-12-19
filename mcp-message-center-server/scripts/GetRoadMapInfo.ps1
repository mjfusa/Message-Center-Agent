param(
  [int]$Top = 10,
  [int]$Skip = 0,
  [string]$Filter = "",
  [string]$OrderBy = "created desc",
  [bool]$Count = $true,
  [string]$McpUrl = "http://localhost:8081/mcp"
)

# Notes:
# - Roadmap uses the 'created' field for date filtering/ordering.
#   Example: "created ge 2025-12-08T00:00:00Z"

$arguments = @{
  top     = $Top
  skip    = $Skip
  count   = $Count
  orderby = $OrderBy
}

if ($Filter) {
  $arguments.filter = $Filter
}

$body = @{
  jsonrpc = "2.0"
  id      = 2
  method  = "tools/call"
  params  = @{
    name      = "getRoadmapInfo"
    arguments = $arguments
  }
} | ConvertTo-Json -Depth 10

$resp = Invoke-WebRequest `
  -Method Post `
  -Uri $McpUrl `
  -ContentType "application/json" `
  -Headers @{ Accept = "application/json, text/event-stream" } `
  -Body $body `
  -SkipHttpErrorCheck

if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
  throw "Request failed ($($resp.StatusCode)):\n$($resp.Content)"
}

$contentType = ($resp.Headers['Content-Type'] | ForEach-Object { [string]$_ }) -join '; '
$raw = [string]$resp.Content

if ($contentType -match 'text/event-stream' -or $raw -match '(?m)^\s*data:') {
  $dataLines = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*data:\s*\S' } | ForEach-Object { $_ -replace '^\s*data:\s*', '' }
  $last = $dataLines | Where-Object { $_ -ne '[DONE]' } | Select-Object -Last 1
  if (-not $last) {
    $raw
    return
  }
  ($last | ConvertFrom-Json) | ConvertTo-Json -Depth 50
  return
}

($raw | ConvertFrom-Json) | ConvertTo-Json -Depth 50
  