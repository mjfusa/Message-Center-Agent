# Check if Microsoft.Entra module is installed
$moduleName = "Microsoft.Entra"
$module = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue

if (-not $module) {
    Write-Host "Required module '$moduleName' is not installed. Installing now..." -ForegroundColor Yellow
    try {
        Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "Successfully installed module '$moduleName'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install module '$moduleName': $_"
        Exit 1
    }
}
else {
    Write-Host "Module '$moduleName' is already installed." -ForegroundColor Green
}

# Connect to Entra with required scopes
try {
    Connect-Entra -Scopes 'Application.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All' -NoWelcome -ErrorAction Stop
}
catch {
    Write-Error "Failed to connect to Entra: $_"
    Write-Host "Make sure you have the Microsoft.Graph.Applications module and you are authorized to create app registrations." -ForegroundColor Yellow
    Exit 1
}
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
$servicePrincipal = New-EntraServicePrincipal -AppId $app.appId

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

# Allow public client flows
# Set-EntraApplication -ApplicationId $app.Id -IsFallbackPublicClient $true

# Set service principal parameters
Set-EntraServicePrincipal -ServicePrincipalId $servicePrincipal.Id -AppRoleAssignmentRequired $false

# # Grant OAuth2 permission
$permissionGrant = New-EntraOauth2PermissionGrant -ClientId $servicePrincipal.Id -ConsentType 'AllPrincipals' -ResourceId $graphServicePrincipal.Id -Scope $delegatedPermission

# Create secret for the application
$secret = New-EntraApplicationPasswordCredential -ApplicationId $app.Id -CustomKeyIdentifier  "MessageCenterAgentSecret" -EndDate (Get-Date).AddYears(1)

# Output app id, app secret, and tenant ID
$appDetails = @{
    clientId = $app.AppId
    tenantId = (Get-EntraTenantDetail).Id
    clientSecret = $secret.SecretText
    appName= $appName
}

# Output the application and service principal details
Write-Host "Application created successfully"
$appDetailsJson= $appDetails | ConvertTo-Json 
Write-Host $appDetailsJson