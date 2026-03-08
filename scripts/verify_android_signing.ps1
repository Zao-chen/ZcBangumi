param(
    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,

    [Parameter(Mandatory = $true)]
    [string]$Alias,

    [Parameter(Mandatory = $true)]
    [string]$StorePassword,

    [Parameter(Mandatory = $true)]
    [string]$KeyPassword,

    [Parameter(Mandatory = $false)]
    [string]$ApkPath,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedSha256
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

$keystoreOutput = keytool -list -v -keystore $KeystorePath -alias $Alias -storepass $StorePassword -keypass $KeyPassword
$keystoreShaLine = ($keystoreOutput | Select-String "SHA256").Line | Select-Object -First 1
if (-not $keystoreShaLine) {
    throw "Cannot read SHA256 from keystore."
}

$keystoreSha = Normalize-Fingerprint(($keystoreShaLine -split ":", 2)[1])
Write-Host "Keystore SHA256: $keystoreSha"

if ($ExpectedSha256) {
    $expected = Normalize-Fingerprint $ExpectedSha256
    if ($keystoreSha -ne $expected) {
        throw "Keystore SHA256 mismatch. Expected=$expected Actual=$keystoreSha"
    }
    Write-Host "Expected SHA256 matched."
}

if ($ApkPath) {
    if (-not (Test-Path $ApkPath)) {
        throw "APK not found: $ApkPath"
    }

    $apksigner = Get-Command apksigner -ErrorAction SilentlyContinue
    if (-not $apksigner) {
        throw "apksigner not found. Install Android build-tools and add apksigner to PATH."
    }

    $apkOutput = apksigner verify --print-certs $ApkPath
    $apkShaLine = ($apkOutput | Select-String "Signer #1 certificate SHA-256 digest").Line | Select-Object -First 1
    if (-not $apkShaLine) {
        throw "Cannot read SHA256 from APK signer certificate."
    }

    $apkSha = Normalize-Fingerprint(($apkShaLine -split ":", 2)[1])
    Write-Host "APK SHA256:      $apkSha"

    if ($apkSha -ne $keystoreSha) {
        throw "APK signer mismatch. Keystore=$keystoreSha APK=$apkSha"
    }

    Write-Host "APK signer matched keystore."
}
