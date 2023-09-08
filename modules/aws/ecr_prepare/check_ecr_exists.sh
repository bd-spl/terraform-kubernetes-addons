#!/bin/bash
# Check ECR repos existance by reading names from a datafile.
# Look up if any matches the given KMS key, and consider such repos shared.
# Return processing results as a JSON.
# Args:
# $1 AWS region
# $2 the input file name with ECR repos names to check existance of
# $3 KMS key to compare results with.
# Login into ECR before running this.
set -eu

datafile="$2"
lookup_kms_key="$3"

OUTPUTS=$(mktemp)
RESULTS=$(mktemp)
trap 'rm -f "$OUTPUTS" "${OUTPUTS}_" "$RESULTS"' EXIT

echo '{}' > "$OUTPUTS"
aws ecr describe-repositories --region "$1" 2>&1 > "$RESULTS"

if [ $? -eq 0 ]; then
  echo '{"success": "true"}' > "${OUTPUTS}__"
else
  echo '{"success": "false", "error_message": "Failed fetching AWS ECR repositories data\"}'
  exit 0
fi

while read repo; do
  repository_url=$(jq -r ".repositories[] | select( .repositoryName==\"$repo\").repositoryUri" "$RESULTS")
  if [ -n "$repository_url" ]; then
    exists=true
    if jq -r ".repositories[] | select( .repositoryName==\"$repo\").encryptionConfiguration.kmsKey" "$RESULTS" | grep -qF "$lookup_kms_key"; then
      shared=true
    else
      shared=false
    fi
  else
    shared=false
    exists=false
    repository_url=null
  fi
  result="{\"exists\":\"$exists\", \"repository_url\":\"$repository_url\", \"name\":\"$repo\", \"shared\": \"$shared\"}"
  jq ".[\"$repo\"]=$result" "$OUTPUTS" > "${OUTPUTS}_"
  mv -f "${OUTPUTS}_" "$OUTPUTS"
done < ${datafile}

# JSON Encode processed results and return it as a "result" string for external TF provider to unmarshal
cat "$OUTPUTS" | python -c 'import json, sys; json.dump(json.dumps(json.load(sys.stdin)), sys.stdout)' > "${OUTPUTS}_"
jq ".result=$(cat ${OUTPUTS}_)" "${OUTPUTS}__"
