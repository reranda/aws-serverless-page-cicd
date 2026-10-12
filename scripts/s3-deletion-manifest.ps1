$bucket = "serverless-page-tfstate-709872263987-eu-west-2"
$region = "eu-west-2"

$data = aws s3api list-object-versions `
  --bucket $bucket `
  --region $region `
  --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    throw "Failed to list S3 object versions."
}

$objects = @(
    foreach ($v in @($data.Versions) + @($data.DeleteMarkers)) {
        if ($null -ne $v) {
            @{
                Key = $v.Key
                VersionId = $v.VersionId
            }
        }
    }
)

"Objects and delete markers to remove: $($objects.Count)"

$manifest = @{
    Objects = $objects
    Quiet = $false
}

$manifest | ConvertTo-Json -Depth 6 |
  Set-Content -Encoding utf8 ".\state-backup\s3-delete-manifest.json"