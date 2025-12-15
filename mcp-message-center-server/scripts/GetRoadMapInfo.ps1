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

Invoke-RestMethod `
  -Method Post `
  -Uri $McpUrl `
  -ContentType "application/json" `
  -Headers @{ Accept = "application/json, text/event-stream" } `
  -Body $body | Out-String
  