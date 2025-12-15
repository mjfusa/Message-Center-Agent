param(
  [string]$McpUrl = "http://localhost:8080/mcp",
  [string]$PublicBaseUrl = ""
)

# This calls the MCP tool getGraphLoginUrl which returns a loginUrl bound to the current MCP session.
# Open the loginUrl in a browser to complete Graph auth for Message Center.

$argsObj = @{}
if ($PublicBaseUrl) {
  $argsObj.publicBaseUrl = $PublicBaseUrl
}

$body = @{
  jsonrpc = "2.0"
  id      = 4
  method  = "tools/call"
  params  = @{
    name      = "getGraphLoginUrl"
    arguments = $argsObj
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri $McpUrl `
  -ContentType "application/json" `
  -Headers @{ Accept = "application/json, text/event-stream" } `
  -Body $body | Out-String
