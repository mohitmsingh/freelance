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
echo "Repository,Secrets Alert Count" > $ORG"_secret_scanning_data.csv"

# Loop through each repository to fetch secret scanning data
for REPO in $REPO_LIST; do
    echo "Fetching secret scanning data for repository: $REPO"
    # Fetch secret scanning data for the repository
    response=$(curl -s -H "Authorization: token $TOKEN" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/$REPO/secret-scanning/alerts")

    if [[ $(echo "$response" | jq -e 'has("message")') == true ]]; then
        message=$(echo "$response" | jq -r '.message')
        echo "$REPO,$message" >> $ORG"_secret_scanning_data.csv"
    else
        output=$(echo "$response" | jq -r '.[] | select(has("number")) | .number')
        if [[ -z $output ]]; then
            echo "$REPO,'unknown'" >> $ORG"_secret_scanning_data.csv"
        else
            count=$(echo "$output" | wc -l)
            # Append repository name and secret scanning count to the Excel file
            echo "$REPO,$count" >> $ORG"_secret_scanning_data.csv"
        fi
    fi
done
echo "Secret scanning data saved to secret_scanning_data.csv"
