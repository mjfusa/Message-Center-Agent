<#
.SYNOPSIS
    Creates a security group for Message Center Agent users and assigns the Message Center Reader role.

.DESCRIPTION
    This script creates a role-assignable Microsoft 365 security group and assigns the Message Center Reader role to it.
    This is the recommended approach for large organizations as it allows admins to manage access
    by simply adding/removing users from the group rather than managing individual role assignments.
    
    IMPORTANT: This script creates a role-assignable group, which requires:
    - Azure AD Premium P1 (or higher) license
    - Privileged Role Administrator or Global Administrator role

.PARAMETER GroupName
    The display name for the security group.
    Default: "Message Center Agent Users"

.PARAMETER GroupDescription
    The description for the security group.
    Default: "Users with access to Message Center Reader role for using the Message Center Agent"

.PARAMETER AddUsers
    Optional array of user principal names to add to the group immediately after creation.

.EXAMPLE
    .\SetupMessageCenterReaderGroup.ps1
    Creates the group with default settings.

.EXAMPLE
    .\SetupMessageCenterReaderGroup.ps1 -GroupName "MC Agent Users" -GroupDescription "Custom description"
    Creates the group with a custom name and description.

.EXAMPLE
    .\SetupMessageCenterReaderGroup.ps1 -AddUsers "user1@contoso.com", "user2@contoso.com"
    Creates the group and immediately adds two users to it.

.NOTES
    Requires Microsoft.Graph PowerShell module.
    The account running this script must have:
    - Privileged Role Administrator or Global Administrator role
    - Group.ReadWrite.All and RoleManagement.ReadWrite.Directory permissions
    
    Requirements:
    - Azure AD Premium P1 (or higher) license for role-assignable groups
    
    After running this script, admins can manage user access by:
    1. Adding users to the group via Microsoft 365 Admin Center
    2. Using the Add-MessageCenterReaderGroupMember.ps1 script (if available)
    3. Using PowerShell: Add-MgGroupMember cmdlet
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$GroupName = "Message Center Agent Users",
    
    [Parameter(Mandatory=$false)]
    [string]$GroupDescription = "Users with access to Message Center Reader role for using the Message Center Agent",
    
    [Parameter(Mandatory=$false)]
    [string[]]$AddUsers
)

# Check if Microsoft.Graph module is installed
Write-Host "Checking for Microsoft.Graph PowerShell module..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
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
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Microsoft.Graph.Users

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Message Center Reader Group Setup Script" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Write-Host "Please sign in with a Privileged Role Administrator or Global Administrator account." -ForegroundColor Yellow
Write-Host "This is required to create role-assignable groups." -ForegroundColor Yellow
Write-Host ""

try {
    Connect-MgGraph -Scopes "Group.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "User.Read.All" -NoWelcome
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "✗ Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Check if group already exists
Write-Host "Checking if group already exists..." -ForegroundColor Cyan
$existingGroup = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue

if ($existingGroup) {
    Write-Host ""
    Write-Host "⚠ A group with the name '$GroupName' already exists!" -ForegroundColor Yellow
    Write-Host "  Group ID: $($existingGroup.Id)" -ForegroundColor White
    Write-Host ""
    
    $response = Read-Host "Do you want to use the existing group? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Operation cancelled. Please run the script again with a different group name." -ForegroundColor Yellow
        Disconnect-MgGraph
        exit 0
    }
    
    $group = $existingGroup
    Write-Host "✓ Using existing group: $GroupName" -ForegroundColor Green
    Write-Host ""
}
else {
    # Create the security group (role-assignable)
    Write-Host "Creating role-assignable security group: $GroupName" -ForegroundColor Cyan
    Write-Host "Note: This group can be assigned to Azure AD roles" -ForegroundColor Yellow
    
    try {
        $mailNickname = $GroupName -replace '[^a-zA-Z0-9]', ''
        if ($mailNickname.Length -gt 64) {
            $mailNickname = $mailNickname.Substring(0, 64)
        }
        
        $groupParams = @{
            DisplayName = $GroupName
            Description = $GroupDescription
            MailEnabled = $false
            SecurityEnabled = $true
            MailNickname = $mailNickname
            IsAssignableToRole = $true
        }
        
        $group = New-MgGroup -BodyParameter $groupParams
        Write-Host "✓ Created role-assignable security group successfully" -ForegroundColor Green
        Write-Host "  Group Name: $($group.DisplayName)" -ForegroundColor White
        Write-Host "  Group ID: $($group.Id)" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Host "✗ Failed to create group: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common causes:" -ForegroundColor Yellow
        Write-Host "  - Insufficient permissions (need Privileged Role Administrator or Global Admin)" -ForegroundColor White
        Write-Host "  - Group name already exists" -ForegroundColor White
        Write-Host "  - Azure AD Premium P1 license required for role-assignable groups" -ForegroundColor White
        Write-Host ""
        Disconnect-MgGraph
        exit 1
    }
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
        Write-Host "✓ Message Center Reader role found" -ForegroundColor Green
    }
    Write-Host ""
}
catch {
    Write-Host "✗ Failed to retrieve role: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

# Check if group already has the role
Write-Host "Checking current role assignments..." -ForegroundColor Cyan
$existingAssignment = Get-MgDirectoryRoleMember -DirectoryRoleId $roleDefinition.Id | 
    Where-Object { $_.Id -eq $group.Id }

if ($existingAssignment) {
    Write-Host "⊘ Group already has Message Center Reader role assigned" -ForegroundColor Yellow
    Write-Host ""
}
else {
    # Assign Message Center Reader role to the group
    Write-Host "Assigning Message Center Reader role to the group..." -ForegroundColor Cyan
    
    try {
        $params = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($group.Id)"
        }
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $roleDefinition.Id -BodyParameter $params
        
        Write-Host "✓ Successfully assigned Message Center Reader role to the group" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "✗ Failed to assign role: $_" -ForegroundColor Red
        Disconnect-MgGraph
        exit 1
    }
}

# Add initial users if specified
if ($AddUsers -and $AddUsers.Count -gt 0) {
    Write-Host "Adding initial users to the group..." -ForegroundColor Cyan
    Write-Host ""
    
    $addedCount = 0
    $failedCount = 0
    
    foreach ($upn in $AddUsers) {
        Write-Host "Processing: $upn" -ForegroundColor White
        
        try {
            $user = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction Stop
            
            if (-not $user) {
                Write-Host "  ✗ User not found: $upn" -ForegroundColor Red
                $failedCount++
                continue
            }
            
            # Check if already a member
            $isMember = Get-MgGroupMember -GroupId $group.Id | Where-Object { $_.Id -eq $user.Id }
            if ($isMember) {
                Write-Host "  ⊘ User is already a member (skipped)" -ForegroundColor Yellow
                continue
            }
            
            # Add user to group
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
            Write-Host "  ✓ Added to group successfully" -ForegroundColor Green
            $addedCount++
        }
        catch {
            Write-Host "  ✗ Failed: $_" -ForegroundColor Red
            $failedCount++
        }
        
        Write-Host ""
    }
    
    Write-Host "Added $addedCount user(s) to the group" -ForegroundColor $(if ($addedCount -gt 0) { "Green" } else { "White" })
    if ($failedCount -gt 0) {
        Write-Host "Failed to add $failedCount user(s)" -ForegroundColor Red
    }
    Write-Host ""
}

# Disconnect
Disconnect-MgGraph | Out-Null

# Summary and next steps
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Group Name:  $($group.DisplayName)" -ForegroundColor White
Write-Host "Group ID:    $($group.Id)" -ForegroundColor White
Write-Host "Role:        Message Center Reader" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "───────────" -ForegroundColor Cyan
Write-Host ""
Write-Host "To grant users access to the Message Center Agent, add them to this group:" -ForegroundColor White
Write-Host ""
Write-Host "Option 1 - Via Microsoft 365 Admin Center:" -ForegroundColor Yellow
Write-Host "  1. Go to https://admin.microsoft.com" -ForegroundColor White
Write-Host "  2. Navigate to Teams & groups > Active teams & groups" -ForegroundColor White
Write-Host "  3. Find and select '$($group.DisplayName)'" -ForegroundColor White
Write-Host "  4. Go to Members tab and click 'Add members'" -ForegroundColor White
Write-Host ""
Write-Host "Option 2 - Via PowerShell:" -ForegroundColor Yellow
Write-Host "  Connect-MgGraph -Scopes 'GroupMember.ReadWrite.All'" -ForegroundColor White
Write-Host "  `$user = Get-MgUser -Filter `"UserPrincipalName eq 'user@contoso.com'`"" -ForegroundColor White
Write-Host "  New-MgGroupMember -GroupId '$($group.Id)' -DirectoryObjectId `$user.Id" -ForegroundColor White
Write-Host ""
Write-Host "Users added to this group will automatically have access to the Message Center Agent!" -ForegroundColor Green
Write-Host ""

exit 0
