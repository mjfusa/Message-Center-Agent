param(
	[int]$Top = 10,
	[int]$Skip = 0,
	[string]$Filter = "",
	[string]$OrderBy = "lastModifiedDateTime desc",
	[bool]$Count = $true,
	[string]$Prefer = "odata.maxpagesize=5",
	[string]$McpUrl = "http://localhost:8080/mcp",

	# Optional: A direct Microsoft Graph access token (local testing / legacy flow).
	# This will be passed as tool argument `accessToken`.
	[string]$GraphAccessToken = "",

	# Optional: A user access token for THIS MCP API (api://<clientId>/access_as_user).
	# If provided, it will be sent as Authorization header so the server can do OBO.
	[string]$McpAccessToken = ""
)

$arguments = @{
	orderby = $OrderBy
	count   = $Count
	prefer  = $Prefer
}

if ($PSBoundParameters.ContainsKey('Top')) {
	$arguments.top = $Top
}

if ($PSBoundParameters.ContainsKey('Skip')) {
	$arguments.skip = $Skip
}

if ($Filter) {
	$arguments.filter = $Filter
}

if ($GraphAccessToken) {
	$arguments.accessToken = $GraphAccessToken
}

$body = @{
	jsonrpc = "2.0"
	id      = 1
	method  = "tools/call"
	params  = @{
		name      = "getMessages"
		arguments = $arguments
	}
} | ConvertTo-Json -Depth 10

$headers = @{ Accept = "application/json, text/event-stream" }
if ($McpAccessToken) {
	$headers.Authorization = "Bearer $McpAccessToken"
}

Invoke-RestMethod `
	-Method Post `
	-Uri $McpUrl `
	-ContentType "application/json" `
	-Headers $headers `
	-Body $body | Out-String
