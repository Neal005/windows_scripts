param (
    [Parameter(Mandatory=$true, HelpMessage="Please provide the JWT token string to verify.")]
    [string]$Token,

    [Parameter(Mandatory=$true, HelpMessage="Please provide the Secret Key used to verify the token signature.")]
    [Security.SecureString]$Secret
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Initializing JWT Signature Verification..." -ForegroundColor Cyan

$parts = $Token.Split('.')
if ($parts.Length -ne 3) {
    Write-Host "[ERROR] Invalid JWT format. The token must contain exactly three segments separated by periods." -ForegroundColor Red
    exit 1
}

# --- Convert SecureString to Plain String safely ---
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
$plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
# ---------------------------------------------------

# 1. VERIFY SIGNATURE
$headerAndPayload = "$($parts[0]).$($parts[1])"
$providedSignature = $parts[2]

# Compute HMACSHA256 hash using the provided Secret Key
$hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($plainSecret))
$hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($headerAndPayload))
$hmac.Dispose()

# Optional: Clear the plain secret from memory right after use for extra security
$plainSecret = $null 

# Convert the computed hash to Base64Url format (JWT Standard)
$computedSignature = [System.Convert]::ToBase64String($hashBytes)
$computedSignature = $computedSignature.Replace('+', '-').Replace('/', '_').TrimEnd('=')

if ($computedSignature -ceq $providedSignature) {
    Write-Host "[SUCCESS] SIGNATURE VALID! (The token is authentic and has not been tampered with)" -ForegroundColor Green
} else {
    Write-Host "[ERROR] SIGNATURE INVALID! (The token has been tampered with, or the Secret Key is incorrect)" -ForegroundColor Red
    Write-Host "Computed Signature: $computedSignature" -ForegroundColor DarkGray
    Write-Host "Provided Signature: $providedSignature" -ForegroundColor DarkGray
    exit 1
}

# 2. CHECK EXPIRATION
$payloadBase64Url = $parts[1]
$payloadBase64 = $payloadBase64Url.Replace('-', '+').Replace('_', '/')

# Apply standard Base64 padding if required
switch ($payloadBase64.Length % 4) {
    2 { $payloadBase64 += "==" }
    3 { $payloadBase64 += "=" }
}

$decodedJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payloadBase64))
$payloadObj = $decodedJson | ConvertFrom-Json

if ($null -ne $payloadObj.exp) {
    # JWT stores expiration time as Unix Epoch (seconds since 1/1/1970)
    $epochOrigin = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $expTimeUtc = $epochOrigin.AddSeconds($payloadObj.exp)
    $nowUtc = [DateTime]::UtcNow

    if ($nowUtc -gt $expTimeUtc) {
        Write-Host "[WARNING] TOKEN EXPIRED! (Expired at: $($expTimeUtc.ToLocalTime()))" -ForegroundColor Yellow
    } else {
        Write-Host "[SUCCESS] TOKEN IS STILL VALID! (Expires at: $($expTimeUtc.ToLocalTime()))" -ForegroundColor Green
    }
} else {
    Write-Host "[INFO] The token does not contain an 'exp' claim. Expiration cannot be verified." -ForegroundColor Cyan
}

$isValid = ($computedSignature -ceq $providedSignature) -and ($null -eq $payloadObj.exp -or $nowUtc -le $expTimeUtc)
Write-Host "`nSummary: This token is $(if ($isValid) {'VALID'} else {'INVALID'})" -ForegroundColor Magenta