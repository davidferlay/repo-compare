#!/bin/bash
#set -x

# Check if at least one argument is provided
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 [directory1] [directory2] [...]"
    exit 1
fi
# Check if the directories exist
for directory in "$@"; do
    if [ ! -d "$directory" ]; then
        echo "Error: Directory '$directory' not found."
    fi
done

# Store passed arguments in an array variable
repos=("$@")
echo "Comparing: ${repos[@]}"

# Iterate through the provided directories
repos_header=""
for repo in "${repos[@]}"; do
    repos_header="${repos_header}exists in ${repo};"
done
#echo "$repos_header"

# Create CSV file with header
echo "${repos_header}role path;last commit author;last commit timestamp;last commit date;last commit short sha;last commit message" > results.csv

# Function to get commit information for a directory path in a repository
get_commit_info() {
  repo=$1
  path=$2
  git --git-dir="$repo/.git" --work-tree="$repo" --no-pager log -1 --invert-grep --grep="versions bump\|Update docs\|change files due to new state build process\|change files due to new build state process\|Backport\|backport\|Init Emile\|Platform: bring changes from zen" --date=iso-strict --format="%an|%ad|%h|%s" -- "$path" 2>/dev/null
}

# Function to convert iso date to timestamp
iso_to_timestamp() {
  date -d "$1" +%s
}

# Associative array to store the latest commit information for each path
declare -A latest_commit_info_timestamp
declare -A latest_commit_info_author
declare -A latest_commit_info_short_sha
declare -A latest_commit_info_message

# Loop through each repository
for repo in "${repos[@]}"; do
  # Find all meta/plasma.yaml files in the repository
  files=$(ag -g "meta/plasma.yaml" "$repo" 2>/dev/null)
  #files=$(ag -g "interaction/softwares/roles/jitsi_exporter/meta/plasma.yaml" "$repo" 2>/dev/null) # Example of last commit being filtered out by git log command and no other commit

  # Loop through each file
  while IFS= read -r file; do
    # Get the directory path without "meta/plasma.yaml" and repository name
    dir_path=$(echo "$file" | sed 's/^[^/]*\/\(.*\)\/meta\/plasma\.yaml$/\1/')

    # Get commit information for the directory path
    commit_info=$(get_commit_info "$repo" "$dir_path")

    # Extract commit date, author, and short sha from commit information
    commit_author=$(echo "$commit_info" | cut -d '|' -f 1)
    commit_short_sha=$(echo "$commit_info" | cut -d '|' -f 3)
    commit_message=$(echo "$commit_info" | cut -d '|' -f 4)
    commit_date=$(echo "$commit_info" | cut -d '|' -f 2)
    # Fix issue where latest commit found has no author/message ?
    if [ -z "${commit_author}" ]; then commit_date="1970-01-01T00:00:00+00:00"; fi

    # Convert commit date to timestamp for comparison
    commit_timestamp=$(iso_to_timestamp "$commit_date")

    echo "----------------------"
    echo "repo: $repo"
    echo "dir_path: $dir_path"
    echo "commit_author: $commit_author"
    echo "commit_short_sha: $commit_short_sha"
    echo "commit_message: $commit_message"
    echo "commit_date: $commit_date"
    echo "commit_timestamp: $commit_timestamp"
    #echo "commit_info: $commit_info"

    # Check if the path has been seen before and if the current commit date is later
    if [ -n "${latest_commit_info_timestamp["$dir_path"]}" ]; then
      if [ "$commit_timestamp" -gt "${latest_commit_info_timestamp["$dir_path"]}" ]; then
        # Update the latest commit information for the path if the current commit date is later
        latest_commit_info_timestamp["$dir_path"]=$commit_timestamp
        latest_commit_info_author["$dir_path"]=$commit_author
        latest_commit_info_short_sha["$dir_path"]=$commit_short_sha
        latest_commit_info_message["$dir_path"]=$commit_message
      fi
    else
      # If the path hasn't been seen before, store the commit information
      latest_commit_info_timestamp["$dir_path"]=$commit_timestamp
      latest_commit_info_author["$dir_path"]=$commit_author
      latest_commit_info_short_sha["$dir_path"]=$commit_short_sha
      latest_commit_info_message["$dir_path"]=$commit_message
    fi
  done <<< "$files"
done

# Check if the same path exists in each repository and print the latest commit information to the CSV file
for path in "${!latest_commit_info_timestamp[@]}"; do
  exists=""
  for repo in "${repos[@]}"; do
    path_exists=""
    if [ -e "$repo/$path" ]; then
      path_exists="1"
    else
      path_exists="0"
    fi
    exists="${exists}${path_exists};"
  done
  latest_commit_info_date=$(date -d @${latest_commit_info_timestamp["$path"]} -u +'%d-%m-%Y')
  echo "${exists}${path};${latest_commit_info_author["$path"]};${latest_commit_info_timestamp["$path"]};${latest_commit_info_date};${latest_commit_info_short_sha["$path"]};${latest_commit_info_message["$path"]}" >> results.csv
done

