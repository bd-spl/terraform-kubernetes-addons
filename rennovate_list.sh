#!/bin/bash
# Reduce the list of pull requests submitted by rennovate by those manually converted into issues (i.e. require extra testing rounds)
# Requires: exported GHTOKEN for the spearlineltd terraform-kubernetes-addons repo, jq, ruby
# Example: GHTOKEN=$EKSADDONSTOKEN bash rennovate_list.sh
set -ue

REPO=${REPO:-spearlineltd/terraform-kubernetes-addons}

# Get issues created from rennovate update PRs
cat > /tmp/ghq << EOF
query issues {
  search(query: "repo:$REPO state:open",
      type: ISSUE, first: 100) {
    pageInfo {
      hasNextPage
      endCursor
    }
    edges {
      node {
        ... on Issue {
          title
          url
          }
        }
      }
    }
  }
EOF
curl -sH "Authorization: bearer $GHTOKEN" -X POST -d "{\"query\": $(ruby -e 'puts `cat /tmp/ghq`.inspect')\"}" https://api.github.com/graphql > /tmp/gh_issues_list
jq -r '.data.search.edges[] | select((.node.title?) and (.node.title|contains("update"))) | .node.title' /tmp/gh_issues_list > /tmp/gh_issues

echo "Known issues for the update PRs submitted by rennovate:"
jq -r '.data.search.edges[] | select((.node.title?) and (.node.title|contains("update"))) | "\(.node.title) \(.node.url)"' /tmp/gh_issues_list | sort -k5
echo '======================================================='; echo

# Get rennovate update PRs
cat > /tmp/ghq << EOF
query issues {
  search(query: "repo:$REPO is:open is:pr",
      type: ISSUE, first: 100) {
    pageInfo {
      hasNextPage
      endCursor
    }
    edges {
      node {
        ... on PullRequest {
          title
          url
          }
        }
      }
    }
  }
EOF
curl -sH "Authorization: bearer $GHTOKEN" -X POST -d "{\"query\": $(ruby -e 'puts `cat /tmp/ghq`.inspect')\"}" https://api.github.com/graphql |\
 jq -r '.data.search.edges[] | select((.node.title?) and (.node.title|contains("update"))) | "\(.node.title) \(.node.url)"' > /tmp/gh_prs

# Reduce the PRs by issues
IFS=$'\n'
while read issue; do
  echo "Omitting rennovate's update PR converted into an issue: $issue"
  grep -v "$issue" /tmp/gh_prs > /tmp/gh_prs_
  mv -f /tmp/gh_prs_ /tmp/gh_prs
done < "/tmp/gh_issues"

echo "Rennovate's updating pull requests not listed in known issues:"
cat /tmp/gh_prs
