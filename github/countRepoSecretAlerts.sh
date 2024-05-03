#!/bin/bash

# Your GitHub personal access token
TOKEN="YOUR_GITHUB_TOKEN"

# GitHub organization name
ORG="YOUR_ORGANIZATION"

# Fetch list of repositories in the organization
REPO_LIST=$(curl -s -H "Authorization: token $TOKEN" \
             -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com/orgs/$ORG/repos" | jq -r '.[].full_name')

# Create an Excel file to store the secret scanning data
echo "Repository,Secrets Count" > secret_scanning_data.csv

# Loop through each repository to fetch secret scanning data
for REPO in $REPO_LIST; do
    echo "Fetching secret scanning data for repository: $REPO"
    # Fetch secret scanning data for the repository
    SECRETS=$(curl -s -H "Authorization: token $TOKEN" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/$REPO/secret-scanning/alerts" | jq '. | length')

    # Append repository name and secret scanning count to the Excel file
    echo "$REPO,$SECRETS" >> secret_scanning_data.csv
done
echo "Secret scanning data saved to secret_scanning_data.csv"
