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

$resp = Invoke-WebRequest `
	-Method Post `
	-Uri $McpUrl `
	-ContentType "application/json" `
	-Headers $headers `
	-Body $body `
	-SkipHttpErrorCheck

if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
	throw "Request failed ($($resp.StatusCode)):\n$($resp.Content)"
}

$contentType = ($resp.Headers['Content-Type'] | ForEach-Object { [string]$_ }) -join '; '
$raw = [string]$resp.Content

if ($contentType -match 'text/event-stream' -or $raw -match '(?m)^\s*data:') {
	# Streamable HTTP transport may respond using SSE. Extract the last JSON payload.
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
