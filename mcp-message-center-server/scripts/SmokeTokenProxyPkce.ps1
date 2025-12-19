[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $ServerBaseUrl = "http://localhost:8080",

  [Parameter(Mandatory = $false)]
  [string] $ClientId = $env:GRAPH_CLIENT_ID,

  [Parameter(Mandatory = $false)]
  [string] $RedirectUri = "http://127.0.0.1:8400/",

  [Parameter(Mandatory = $false)]
  [string] $Scope = $env:MCP_OAUTH_SCOPES,

  [Parameter(Mandatory = $false)]
  [string] $LoginHint
)

function Require-Value([string] $Name, [string] $Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Missing required value: $Name"
  }
  return $Value
}

function ConvertTo-Base64Url([byte[]] $Bytes) {
  $b64 = [Convert]::ToBase64String($Bytes)
  return $b64.TrimEnd('=') -replace '\+', '-' -replace '/', '_'
}

function New-CodeVerifier() {
  # RFC 7636: 43..128 chars from unreserved set.
  $bytes = New-Object byte[] 64
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  $verifier = ConvertTo-Base64Url $bytes
  if ($verifier.Length -lt 43) {
    # Pad deterministically if base64url came out short (rare).
    $verifier = $verifier.PadRight(43, 'A')
  }
  if ($verifier.Length -gt 128) {
    $verifier = $verifier.Substring(0, 128)
  }
  return $verifier
}

function New-CodeChallengeS256([string] $Verifier) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Verifier)
    $hash = $sha.ComputeHash($bytes)
    return ConvertTo-Base64Url $hash
  } finally {
    $sha.Dispose()
  }
}

$ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')
$clientId = Require-Value "ClientId (or GRAPH_CLIENT_ID env var)" $ClientId

if ([string]::IsNullOrWhiteSpace($Scope)) {
  $Scope = "openid profile offline_access api://$clientId/access_as_user"
}

$codeVerifier = New-CodeVerifier
$codeChallenge = New-CodeChallengeS256 $codeVerifier
$state = [Guid]::NewGuid().ToString('N')

$authorizeUrl = "$ServerBaseUrl/authorize?client_id=$([Uri]::EscapeDataString($clientId))" +
  "&response_type=code" +
  "&redirect_uri=$([Uri]::EscapeDataString($RedirectUri))" +
  "&response_mode=query" +
  "&scope=$([Uri]::EscapeDataString($Scope))" +
  "&state=$([Uri]::EscapeDataString($state))" +
  "&code_challenge_method=S256" +
  "&code_challenge=$([Uri]::EscapeDataString($codeChallenge))"

if (-not [string]::IsNullOrWhiteSpace($LoginHint)) {
  $authorizeUrl += "&login_hint=$([Uri]::EscapeDataString($LoginHint))"
}

Write-Host "\n(1) Open this URL in a browser to sign in:" -ForegroundColor Cyan
Write-Host $authorizeUrl

Write-Host "\n(2) After sign-in, the browser will redirect to $RedirectUri." -ForegroundColor Cyan
Write-Host "    If nothing is listening on that port, that's OK — copy the FULL redirected URL from the address bar." -ForegroundColor Cyan

$redirectedUrl = Read-Host "\nPaste the FULL redirected URL here"

try {
  $uri = [Uri]$redirectedUrl
} catch {
  throw "Input was not a valid URL. Paste the full redirected URL (including ?code=...)."
}

$qs = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
$code = $qs.Get('code')
$returnedState = $qs.Get('state')

if ([string]::IsNullOrWhiteSpace($code)) {
  throw "No 'code' found in the pasted URL query string."
}
if (-not [string]::IsNullOrWhiteSpace($returnedState) -and $returnedState -ne $state) {
  throw "State mismatch. Expected $state but got $returnedState"
}

Write-Host "\n(3) Exchanging code at $ServerBaseUrl/token ..." -ForegroundColor Cyan

$body = [ordered]@{
  client_id = $clientId
  grant_type = 'authorization_code'
  redirect_uri = $RedirectUri
  code = $code
  code_verifier = $codeVerifier
  scope = $Scope
}

$response = Invoke-RestMethod -Method Post -Uri "$ServerBaseUrl/token" -ContentType 'application/x-www-form-urlencoded' -Body $body

Write-Host "\nToken response:" -ForegroundColor Green
$response | ConvertTo-Json -Depth 50

Write-Host "\nDone." -ForegroundColor Green
