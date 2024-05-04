# Your GitHub personal access token
$TOKEN = "YOUR_GITHUB_TOKEN"

# GitHub organization name
$ORG = "YOUR_ORGANIZATION"

# Fetch list of repositories in the organization
$REPO_LIST = (Invoke-RestMethod -Uri "https://api.github.com/orgs/$ORG/repos" -Headers @{
    Authorization = "token $TOKEN"
    Accept = "application/vnd.github.v3+json"
}).full_name

# Create a CSV file to store the secret scanning data
"Repository,Secrets Alert Count" | Out-File -FilePath "$ORG\_secret_scanning_data.csv" -Encoding utf8

# Loop through each repository to fetch secret scanning data
foreach ($REPO in $REPO_LIST) {
    Write-Host "Fetching secret scanning data for repository: $REPO"
    # Fetch secret scanning data for the repository
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/secret-scanning/alerts" -Headers @{
        Authorization = "token $TOKEN"
        Accept = "application/vnd.github.v3+json"
    }

    if ($response.message) {
        $message = $response.message
        "$REPO,$message" | Out-File -FilePath "$ORG\_secret_scanning_data.csv" -Append -Encoding utf8
    } else {
        $output = $response | Where-Object { $_.number } | Select-Object -ExpandProperty number
        if (-not $output) {
            "$REPO,'unknown'" | Out-File -FilePath "$ORG\_secret_scanning_data.csv" -Append -Encoding utf8
        } else {
            $count = $output.Count
            # Append repository name and secret scanning count to the CSV file
            "$REPO,$count" | Out-File -FilePath "$ORG\_secret_scanning_data.csv" -Append -Encoding utf8
        }
    }
}

Write-Host "Secret scanning data saved to ${ORG}_secret_scanning_data.csv"
