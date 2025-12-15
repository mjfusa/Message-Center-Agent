param(
  [int]$Top = 5,
  [int]$Skip = 0,
  [string]$Filter = "",
  [string]$OrderBy = "lastModifiedDateTime desc",
  [switch]$CountOnly,
  [string]$McpUrl = "http://localhost:8080/mcp",
  [string]$GraphAccessToken = ""
)

# Notes:
# - If you don't pass -GraphAccessToken, the MCP server will try:
#   1) GRAPH_ACCESS_TOKEN env var, then
#   2) OAuth token cached for your MCP session (after browser sign-in).
# - To do browser sign-in, run .\GetGraphLoginUrl.ps1 and open the URL.

$arguments = @{
  orderby = $OrderBy
  count   = $true
  top     = $Top
  skip    = $Skip
}

if ($CountOnly) {
  $arguments.top = 0
}

if ($Filter) {
  $arguments.filter = $Filter
}

if ($GraphAccessToken) {
  $arguments.accessToken = $GraphAccessToken
}

$body = @{
  jsonrpc = "2.0"
  id      = 3
  method  = "tools/call"
  params  = @{
    name      = "getMessages"
    arguments = $arguments
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri $McpUrl `
  -ContentType "application/json" `
  -Headers @{ Accept = "application/json, text/event-stream" } `
  -Body $body | Out-String
