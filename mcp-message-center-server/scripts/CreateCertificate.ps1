<#{
.SYNOPSIS
Creates a self-signed certificate for Entra app auth and exports common formats.

.DESCRIPTION
Creates an RSA self-signed certificate suitable for:
- Uploading the public cert to an Entra App Registration (Certificates & secrets > Certificates)
- Storing the PEM private key in Azure Key Vault as a *secret* for this repo's certificate-based auth

Outputs:
- .cer (DER): public cert for Entra upload
- .pem (CERTIFICATE): public cert in PEM
- .key.pem (PRIVATE KEY, PKCS#8): private key in PEM (ideal for Key Vault secret)
- .pfx (optional): convenience bundle for Windows tooling

.EXAMPLE
pwsh -File .\scripts\CreateCertificate.ps1 -Name graph-obo -DnsName localhost -OutputDir .\certs

.EXAMPLE
# Create cert and export files without installing into the Windows cert store
pwsh -File .\scripts\CreateCertificate.ps1 -Name graph-obo -NoInstallToStore

.EXAMPLE
# Create cert with a PFX (will prompt for password)
pwsh -File .\scripts\CreateCertificate.ps1 -Name graph-obo -ExportPfx
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $Name = 'graph-client-cert',

    # If provided, used as SAN entries (recommended). If not provided, Subject CN is used.
    [Parameter(Mandatory = $false)]
    [string[]] $DnsName,

    [Parameter(Mandatory = $false)]
    [int] $KeyLength = 2048,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int] $ValidYears = 2,

    [Parameter(Mandatory = $false)]
    [string] $CertStoreLocation = 'cert:\CurrentUser\My',

    [Parameter(Mandatory = $false)]
    [string] $OutputDir = 'C:\temp',

    [Parameter(Mandatory = $false)]
    [switch] $NoInstallToStore,

    [Parameter(Mandatory = $false)]
    [switch] $ExportPfx,

    [Parameter(Mandatory = $false)]
    [SecureString] $PfxPassword,

    [Parameter(Mandatory = $false)]
    [switch] $IncludeClientAuthEku
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-PemFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Header,
        [Parameter(Mandatory = $true)][byte[]] $DerBytes
    )

    $b64 = [Convert]::ToBase64String($DerBytes)
    $wrapped = ($b64 -split '(.{1,64})' | Where-Object { $_ -and $_.Trim() }) -join "`n"
    $pem = "-----BEGIN $Header-----`n$wrapped`n-----END $Header-----`n"
    Set-Content -Path $Path -Value $pem -Encoding ascii
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$notAfter = (Get-Date).AddYears($ValidYears)
$subject = "CN=$Name"

$textExtensions = @()
if ($IncludeClientAuthEku) {
    # Enhanced Key Usage: Client Authentication (1.3.6.1.5.5.7.3.2)
    $textExtensions += '2.5.29.37={text}1.3.6.1.5.5.7.3.2'
}

$newCertParams = @{
    KeyExportPolicy   = 'Exportable'
    KeyAlgorithm      = 'RSA'
    KeyLength         = $KeyLength
    HashAlgorithm     = 'SHA256'
    NotAfter          = $notAfter
    KeyUsage          = 'DigitalSignature'
    FriendlyName      = $Name
}

if ($textExtensions.Count -gt 0) {
    $newCertParams['TextExtension'] = $textExtensions
}

if ($DnsName -and $DnsName.Count -gt 0) {
    $newCertParams['DnsName'] = $DnsName
} else {
    $newCertParams['Subject'] = $subject
}

# New-SelfSignedCertificate requires a cert store context to create keys reliably.
# We always create in a user-accessible store, and optionally remove it after export.
$newCertParams['CertStoreLocation'] = $CertStoreLocation

$cert = New-SelfSignedCertificate @newCertParams

# Export public cert (.cer) for Entra upload
$cerPath = Join-Path $OutputDir "$Name.cer"
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

# Export PEM public cert
$certPemPath = Join-Path $OutputDir "$Name.pem"
$cerDer = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
Write-PemFile -Path $certPemPath -Header 'CERTIFICATE' -DerBytes $cerDer

# Export PEM private key (PKCS#8) - ideal for Key Vault secret value
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
if (-not $rsa) {
    throw 'Failed to access RSA private key from the generated certificate.'
}

try {
    $pkcs8 = $rsa.ExportPkcs8PrivateKey()
} finally {
    $rsa.Dispose()
}

$privateKeyPemPath = Join-Path $OutputDir "$Name.key.pem"
Write-PemFile -Path $privateKeyPemPath -Header 'PRIVATE KEY' -DerBytes $pkcs8

# Optional: export PFX (includes private key)
$pfxPath = $null
if ($ExportPfx) {
    if (-not $PfxPassword) {
        $PfxPassword = Read-Host -AsSecureString "Enter a password to protect the exported PFX"
    }
    $pfxPath = Join-Path $OutputDir "$Name.pfx"
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $PfxPassword | Out-Null
}

Write-Host "\nCertificate created." -ForegroundColor Green
Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "Public cert (upload to Entra App Registration): $cerPath" -ForegroundColor Cyan
Write-Host "Public cert PEM: $certPemPath" -ForegroundColor Cyan
Write-Host "Private key PEM (store in Key Vault secret): $privateKeyPemPath" -ForegroundColor Cyan
if ($pfxPath) {
    Write-Host "PFX: $pfxPath" -ForegroundColor Cyan
}

if ($NoInstallToStore) {
    try {
        Remove-Item -LiteralPath ("cert:\\CurrentUser\\My\\" + $cert.Thumbprint) -ErrorAction Stop
        Write-Host "Removed cert from store: $CertStoreLocation" -ForegroundColor DarkGray
    } catch {
        Write-Host "Warning: failed to remove cert from store: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

[pscustomobject]@{
    Name             = $Name
    Thumbprint       = $cert.Thumbprint
    NotAfter         = $cert.NotAfter
    CerPath          = $cerPath
    CertPemPath      = $certPemPath
    PrivateKeyPemPath = $privateKeyPemPath
    PfxPath          = $pfxPath
}
