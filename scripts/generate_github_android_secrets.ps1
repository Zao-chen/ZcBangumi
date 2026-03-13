param(
    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,

    [Parameter(Mandatory = $true)]
    [string]$Alias,

    [Parameter(Mandatory = $true)]
    [string]$StorePassword,

    [Parameter(Mandatory = $true)]
    [string]$KeyPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-Fingerprint([string]$value) {
    return ($value -replace ":", "" -replace "\s", "").ToUpperInvariant()
}

if (-not (Test-Path $KeystorePath)) {
    throw "Keystore not found: $KeystorePath"
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw "keytool not found. Please install JDK and ensure keytool is on PATH."
}

$keystoreBytes = [IO.File]::ReadAllBytes((Resolve-Path $KeystorePath))
$keystoreBase64 = [Convert]::ToBase64String($keystoreBytes)

$keytoolOutput = @(keytool -list -v -keystore $KeystorePath -alias $Alias -storepass $StorePassword -keypass $KeyPassword 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw (($keytoolOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine)
}

$shaLine = $keytoolOutput |
    Select-String "SHA256" |
    ForEach-Object { $_.Line } |
    Select-Object -First 1
if (-not $shaLine) {
    throw "Cannot read SHA256 from keystore. Check alias/passwords."
}

$sha256 = Normalize-Fingerprint(($shaLine -split ":", 2)[1])

Write-Host "===== GitHub Actions Secrets ====="
Write-Host "ANDROID_KEYSTORE_BASE64=$keystoreBase64"
Write-Host "ANDROID_STORE_PASSWORD=$StorePassword"
Write-Host "ANDROID_KEY_ALIAS=$Alias"
Write-Host "ANDROID_KEY_PASSWORD=$KeyPassword"
Write-Host "ANDROID_CERT_SHA256=$sha256"
Write-Host "=================================="
Write-Host "Paste each value into GitHub: Settings -> Secrets and variables -> Actions"
