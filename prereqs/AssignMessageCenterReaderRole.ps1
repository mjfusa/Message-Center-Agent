<#
.SYNOPSIS
    Assigns the Message Center Reader role to one or more users.

.DESCRIPTION
    This script assigns the Message Center Reader role to specified users in your Microsoft 365 tenant.
    Users can be specified directly via the UserPrincipalNames parameter or imported from a CSV file.
    This role is required for users to access the Message Center Agent.

.PARAMETER UserPrincipalNames
    Array of user principal names (email addresses) to assign the role to.
    Example: "user1@contoso.com", "user2@contoso.com"

.PARAMETER FromCsvFile
    Switch parameter to indicate that users should be imported from a CSV file.

.PARAMETER CsvPath
    Path to the CSV file containing user information.
    The CSV must have a column named "UserPrincipalName".
    Example CSV path: ".\users.csv"

.EXAMPLE
    .\AssignMessageCenterReaderRole.ps1 -UserPrincipalNames "user1@contoso.com", "user2@contoso.com"
    Assigns the role to two specific users.

.EXAMPLE
    .\AssignMessageCenterReaderRole.ps1 -FromCsvFile -CsvPath ".\users.csv"
    Assigns the role to all users listed in the CSV file.

.NOTES
    Requires Microsoft.Graph PowerShell module.
    The account running this script must have the RoleManagement.ReadWrite.Directory permission.
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$UserPrincipalNames,
    
    [Parameter(Mandatory=$false)]
    [switch]$FromCsvFile,
    
    [Parameter(Mandatory=$false)]
    [string]$CsvPath
)

# Validate parameters
if (-not $FromCsvFile -and -not $UserPrincipalNames) {
    Write-Host "ERROR: You must specify either -UserPrincipalNames or use -FromCsvFile with -CsvPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\AssignMessageCenterReaderRole.ps1 -UserPrincipalNames 'user1@contoso.com', 'user2@contoso.com'"
    Write-Host "  .\AssignMessageCenterReaderRole.ps1 -FromCsvFile -CsvPath '.\users.csv'"
    exit 1
}

if ($FromCsvFile -and -not $CsvPath) {
    Write-Host "ERROR: -CsvPath is required when using -FromCsvFile" -ForegroundColor Red
    exit 1
}

# Check if Microsoft.Graph module is installed
Write-Host "Checking for Microsoft.Graph PowerShell module..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement)) {
    Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
        Write-Host "✓ Microsoft.Graph module installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to install Microsoft.Graph module: $_" -ForegroundColor Red
        exit 1
    }
}

# Import required modules
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Microsoft.Graph.Users

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Message Center Reader Role Assignment Script" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Write-Host "Please sign in with an account that has RoleManagement.ReadWrite.Directory permission." -ForegroundColor Yellow
Write-Host ""

try {
    Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory", "User.Read.All" -NoWelcome
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "✗ Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Get Message Center Reader role
Write-Host "Retrieving Message Center Reader role..." -ForegroundColor Cyan
try {
    $roleDefinition = Get-MgDirectoryRole -Filter "DisplayName eq 'Message Center Reader'" -ErrorAction SilentlyContinue
    
    if (-not $roleDefinition) {
        Write-Host "Message Center Reader role not activated. Activating now..." -ForegroundColor Yellow
        $roleTemplate = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq "Message Center Reader" }
        
        if (-not $roleTemplate) {
            Write-Host "✗ Message Center Reader role template not found" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
        
        $roleDefinition = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
        Write-Host "✓ Message Center Reader role activated" -ForegroundColor Green
    }
    else {
        Write-Host "✓ Message Center Reader role found (ID: $($roleDefinition.Id))" -ForegroundColor Green
    }
    Write-Host ""
}
catch {
    Write-Host "✗ Failed to retrieve role: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# Process users from CSV if specified
if ($FromCsvFile) {
    if (-not (Test-Path $CsvPath)) {
        Write-Host "✗ CSV file not found: $CsvPath" -ForegroundColor Red
        Disconnect-MgGraph
        exit 1
    }
    
    Write-Host "Importing users from CSV: $CsvPath" -ForegroundColor Cyan
    try {
        $csvData = Import-Csv $CsvPath
        if (-not $csvData[0].PSObject.Properties.Name -contains "UserPrincipalName") {
            Write-Host "✗ CSV file must contain a 'UserPrincipalName' column" -ForegroundColor Red
            Disconnect-MgGraph
            exit 1
        }
        $UserPrincipalNames = $csvData | Select-Object -ExpandProperty UserPrincipalName
        Write-Host "✓ Found $($UserPrincipalNames.Count) user(s) in CSV" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "✗ Failed to import CSV: $_" -ForegroundColor Red
        Disconnect-MgGraph
        exit 1
    }
}

# Assign role to each user
Write-Host "Assigning Message Center Reader role to users..." -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0
$skippedCount = 0

foreach ($upn in $UserPrincipalNames) {
    Write-Host "Processing: $upn" -ForegroundColor White
    
    try {
        # Get user
        $user = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction Stop
        
        if (-not $user) {
            Write-Host "  ✗ User not found: $upn" -ForegroundColor Red
            $failCount++
            continue
        }
        
        # Check if user already has the role
        $existingAssignment = Get-MgDirectoryRoleMember -DirectoryRoleId $roleDefinition.Id | 
            Where-Object { $_.Id -eq $user.Id }
        
        if ($existingAssignment) {
            Write-Host "  ⊘ User already has Message Center Reader role (skipped)" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
        
        # Assign role
        $params = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $roleDefinition.Id -BodyParameter $params
        
        Write-Host "  ✓ Successfully assigned Message Center Reader role" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        $failCount++
    }
    
    Write-Host ""
}

# Summary
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Assignment Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Total users processed: $($UserPrincipalNames.Count)" -ForegroundColor White
Write-Host "Successfully assigned: $successCount" -ForegroundColor Green
Write-Host "Already had role:      $skippedCount" -ForegroundColor Yellow
Write-Host "Failed:                $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null
Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Cyan
Write-Host ""

if ($successCount -gt 0) {
    Write-Host "✓ Users can now access the Message Center Agent" -ForegroundColor Green
}

exit 0
