param (
    [Parameter(Mandatory=$true, HelpMessage="Please provide the JWT token string.")]
    [string]$Token
)

# Enforce UTF-8 encoding for standard console output to properly render localized characters.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Initializing JWT payload decoding sequence..." -ForegroundColor Cyan

# Validate JWT structure (Header.Payload.Signature)
$jwtSegments = $Token.Split('.')
if ($jwtSegments.Length -ne 3) {
    Write-Host "[ERROR] Invalid JWT format. The token must contain exactly three segments separated by periods." -ForegroundColor Red
    exit 1
}

$payloadBase64Url = $jwtSegments[1]

# Convert Base64Url encoding to standard Base64 encoding
$payloadBase64 = $payloadBase64Url.Replace('-', '+').Replace('_', '/')

# Apply standard Base64 padding if required
switch ($payloadBase64.Length % 4) {
    2 { $payloadBase64 += "==" }
    3 { $payloadBase64 += "=" }
}

try {
    # Decode the Base64 payload into a byte array
    $decodedBytes = [System.Convert]::FromBase64String($payloadBase64)
    
    # Convert byte array to UTF-8 string
    $decodedJsonString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)

    Write-Host "`n[SUCCESS] Payload decoded successfully." -ForegroundColor Green
    Write-Host "================ JWT PAYLOAD CLAIMS ================" -ForegroundColor Yellow
    
    # Format and output the JSON structure
    $decodedJsonString | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
}
catch {
    Write-Host "[ERROR] Failed to decode the JWT payload. The Base64 string may be malformed or corrupted." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkGray
    exit 1
}
