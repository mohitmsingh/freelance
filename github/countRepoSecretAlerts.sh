#!/bin/bash

# Your GitHub personal access token
TOKEN=""

# GitHub organization name
ORG=""

rm -rf "${ORG}_repo_list.txt" "${ORG}_secret_scanning_report.csv" ${ORG}
mkdir ${ORG}
# Initialize an empty array to store repository names
REPO_LIST=()

# Fetch list of repositories in the organization from all pages
page=1
while true; do
    response=$(curl -s -H "Authorization: token $TOKEN" \
               -H "Accept: application/vnd.github.v3+json" \
               "https://api.github.com/orgs/$ORG/repos?page=$page&per_page=100")

    # Check if the response is empty or if it contains an error message
    if [ -z "$response" ]; then
        echo "Error: Empty response from GitHub API."
        exit 1
    elif [[ $(echo "$response" | jq -e 'has("message")') == true ]]; then
        message=$(echo "$response" | jq -r '.message')
        echo "Error: $message"
        exit 1
    fi

    # Extract repository names from the response and add them to the array
    repos=$(echo "$response" | jq -r '.[].name')
    REPO_LIST+=( $repos )

    # Check if there are more pages to fetch
    if [ $(echo "$response" | jq -e '. | length') -lt 100 ]; then
        break
    fi

    # Increment page number for the next request
    ((page++))
done

# Save the list of repositories to a file
for repo in "${REPO_LIST[@]}"; do
    echo "$repo" >> "${ORG}_repo_list.txt"
done

# Create an Excel file to store the secret scanning data
echo "Repository,Secrets Alert Count" > "${ORG}_secret_scanning_report.csv"

# Loop through each repository to fetch secret scanning data
for REPO in "${REPO_LIST[@]}"; do
    echo "Fetching secret scanning data for repository: $REPO"
    # Fetch secret scanning data for the repository
    response=$(curl -s -H "Authorization: token $TOKEN" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/$ORG/$REPO/secret-scanning/alerts")
    
    echo "${response}" > ${ORG}/${REPO}_secret_alerts.json

    if [[ $(echo "$response" | jq -e 'has("message")') == true ]]; then
        message=$(echo "$response" | jq -r '.message')
        echo "$REPO,$message" >> "${ORG}_secret_scanning_report.csv"
    else
        count=$(echo "$response" | jq length)
        # Check if response is an array before counting its length
        if [[ $count != 0 ]]; then
            echo "$REPO,$count" >> "${ORG}_secret_scanning_report.csv"
        else
            echo "$REPO,Empty" >> "${ORG}_secret_scanning_report.csv"
        fi
    fi
done
echo "Secret scanning data saved to ${ORG}_secret_scanning_report.csv"
