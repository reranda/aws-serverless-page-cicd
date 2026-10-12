
param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName,

    [string]$Region = "eu-west-2",

    [string]$OutputPath = ".\state-backup\s3-delete-manifest.json"
)

$ErrorActionPreference = "Stop"

# Ensure the output directory exists.
$directory = Split-Path -Parent $OutputPath

if ($directory -and !(Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force |
        Out-Null
}

# Retrieve all object versions and delete markers.
$json = aws s3api list-object-versions `
    --bucket $BucketName `
    --region $Region `
    --output json

if ($LASTEXITCODE -ne 0) {
    throw "Failed to retrieve S3 object versions."
}

$data = $json | ConvertFrom-Json

$objects = @(
    foreach ($item in @($data.Versions) + @($data.DeleteMarkers)) {
        if ($null -ne $item) {
            @{
                Key       = $item.Key
                VersionId = $item.VersionId
            }
        }
    }
)

Write-Host "Bucket: $BucketName"
Write-Host "Object versions and delete markers: $($objects.Count)"

if ($objects.Count -eq 0) {
    Write-Host "No object versions or delete markers found."
    return
}

# Create the manifest only. Do not delete objects.
$manifest = @{
    Objects = $objects
    Quiet   = $false
}

$manifest |
    ConvertTo-Json -Depth 6 |
    Set-Content -Path $OutputPath -Encoding utf8

Write-Host "Deletion manifest saved to: $OutputPath"
Write-Host "No S3 objects have been deleted."
