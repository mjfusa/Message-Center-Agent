# Increase JSON conversion depth for this session
$PSDefaultParameterValues['ConvertTo-Json:Depth'] = 10

# Connect to Entra with required scopes
Connect-Entra -Scopes 'Application.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All' -NoWelcome
# Define application name and redirect URI
$appName = "MessageCenterAgent-reg"
$redirectUri = 'https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect'

# check if the application already exists
$existingApp = Get-EntraApplication -Filter "DisplayName eq '$appName'" -ErrorAction SilentlyContinue   
if ($existingApp) {
    Write-Host "Application $appName already exists with ID: "  -NoNewline
    Write-Host "$($existingApp.AppId)" -ForegroundColor Yellow
    Exit 0
} else {
    Write-Host "Creating new application registration..."
}

# Define delegated permission and Graph API ID
$delegatedPermission = 'ServiceMessage.Read.All'
$graphApiId = '00000003-0000-0000-c000-000000000000'


$web = @{
    redirectUris = @("https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect")
}

# Create a new application
$app = New-EntraApplication -DisplayName $appName -Web $web 

# Create a service principal for the application
$servicePrincipal = New-EntraServicePrincipal -AppId $app.AppId

# Get Graph service principal
$graphServicePrincipal = Get-EntraServicePrincipal -Filter "AppId eq '$graphApiId'"

# Create resource access object
$resourceAccessDelegated = New-Object Microsoft.Open.MSGraph.Model.ResourceAccess
$resourceAccessDelegated.Id = ((Get-EntraServicePrincipal -ServicePrincipalId $graphServicePrincipal.Id).Oauth2PermissionScopes | Where-Object { $_.Value -eq $delegatedPermission }).Id
$resourceAccessDelegated.Type = 'Scope'

# Create required resource access object
$requiredResourceAccessDelegated = New-Object Microsoft.Open.MSGraph.Model.RequiredResourceAccess
$requiredResourceAccessDelegated.ResourceAppId = $graphApiId
$requiredResourceAccessDelegated.ResourceAccess = $resourceAccessDelegated

# Set application required resource access
Set-EntraApplication -ApplicationId $app.Id -RequiredResourceAccess $requiredResourceAccessDelegated

# Set service principal parameters
Set-EntraServicePrincipal -ServicePrincipalId $servicePrincipal.Id -AppRoleAssignmentRequired $True

# # Grant OAuth2 permission
$permissionGrant = New-EntraOauth2PermissionGrant -ClientId $servicePrincipal.Id -ConsentType 'AllPrincipals' -ResourceId $graphServicePrincipal.Id -Scope $delegatedPermission

# # Get and filter OAuth2 permission grants
#Get-EntraOAuth2PermissionGrant -All | Where-Object { $_.Id -eq $permissionGrant.Id }

# Create secret for the application
$secret = New-EntraApplicationPasswordCredential -ApplicationId $app.Id -CustomKeyIdentifier  "MessageCenterAgentSecret" -EndDate (Get-Date).AddYears(1)

# Output app id, app seceret, and tenant ID to a json file
$appDetails = @{
    clientId = $app.AppId
    tenantId = (Get-EntraTenantDetail).Id
    clientSecret = $secret.SecretText
    appName= $appName
}

# Output the application and service principal details
Write-Host "Application created successfully"
$appDetailsJson= $appDetails | ConvertTo-Json -Depth 100
Write-Host $appDetailsJson