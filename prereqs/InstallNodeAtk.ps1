# InstallNodeAtk.ps1 - Install Node.js and Microsoft 365 Agents Toolkit CLI
# This script checks if Node.js is installed with at least version 20, installs it if needed,
# and then installs the Microsoft 365 Agents Toolkit CLI

# Function to check if a command exists
function Test-CommandExists {
    param ($command)
    
    $exists = $null -ne (Get-Command -Name $command -ErrorAction SilentlyContinue)
    return $exists
}

# Function to display error and exit
function Exit-WithError {
    param (
        [string]$ErrorMessage
    )
    
    Write-Host "ERROR: $ErrorMessage" -ForegroundColor Red
    exit 1
}

# Check if Node.js is installed
Write-Host "Checking if Node.js is installed..." -ForegroundColor Cyan
$nodeInstalled = Test-CommandExists "node"

if (-not $nodeInstalled) {
    Write-Host "Node.js is not installed. Installing using winget..." -ForegroundColor Yellow
    
    # Check if winget is available
    if (-not (Test-CommandExists "winget")) {
        Exit-WithError "winget is not available. Please install App Installer from the Microsoft Store."
    }
    
    # Install Node.js using winget
    try {
        Write-Host "Installing Node.js latest version" -ForegroundColor Cyan
        winget install OpenJS.NodeJS  --accept-source-agreements --accept-package-agreements
        
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "Failed to install Node.js. winget returned error code: $LASTEXITCODE"
        }
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
    catch {
        Exit-WithError "Failed to install Node.js: $_"
    }
    
    # Verify installation succeeded
    if (-not (Test-CommandExists "node")) {
        Exit-WithError "Node.js installation verification failed. Please try installing manually."
    }
    
    Write-Host "Node.js installed successfully!" -ForegroundColor Green
}
else {
    # Check Node.js version
    try {
        $nodeVersion = (node -v).Substring(1)  # Remove the v prefix
        $versionParts = $nodeVersion.Split('.')
        $majorVersion = [int]$versionParts[0]
        
        if ($majorVersion -lt 20) {
            Write-Host "Node.js version $nodeVersion is installed, but version 20 or higher is required." -ForegroundColor Yellow
            Write-Host "Updating Node.js using winget..." -ForegroundColor Cyan
            
            # Install/update Node.js using winget
            winget install OpenJS.NodeJS -v "~20" --accept-source-agreements --accept-package-agreements
            
            if ($LASTEXITCODE -ne 0) {
                Exit-WithError "Failed to update Node.js. winget returned error code: $LASTEXITCODE"
            }
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            Write-Host "Node.js updated successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "Node.js version $nodeVersion is already installed (meets minimum requirement)." -ForegroundColor Green
        }
    }
    catch {
        Exit-WithError "Failed to check Node.js version: $_"
    }
}

# Install Microsoft 365 Agents Toolkit CLI
Write-Host "`nInstalling Microsoft 365 Agents Toolkit CLI..." -ForegroundColor Cyan

try {
    # Check if m365 agents toolkit cli is already installed
    $atkInstalled = Test-CommandExists "atk"
    
    if ($atkInstalled) {
        Write-Host "Microsoft 365 Agents Toolkit CLI is already installed. Updating..." -ForegroundColor Yellow
    }
    
    # Install or update M365 Agents Toolkit CLI
    npm install -g @microsoft/m365agentstoolkit-cli
    
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Failed to install Microsoft 365 Agents Toolkit CLI. npm returned error code: $LASTEXITCODE"
    }
    
    # Verify installation succeeded
    if (-not (Test-CommandExists "atk")) {
        Exit-WithError "Microsoft 365 Agents Toolkit CLI installation verification failed."
    }
    
    Write-Host "Microsoft 365 Agents Toolkit CLI installed successfully!" -ForegroundColor Green
}
catch {
    Exit-WithError "Failed to install Microsoft 365 Agents Toolkit CLI: $_"
}

# Final success message
Write-Host "`nSetup completed successfully!" -ForegroundColor Green
Write-Host "Now you can now use the Microsoft 365 Agents Toolkit CLI with the 'atk' command." -ForegroundColor Cyan