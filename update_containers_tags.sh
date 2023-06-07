#!/bin/bash
# Fetch containers images data from helm-dependencies.yaml and update tags info
# Requires: jq, yq, pyyaml, podman

NAMESELECTOR='if .registry? then "\(.registry.registry)/" else "" end + if .name.image? then .name.image else .name.repository end'

yq '.dependencies[]|select(.containers?)[]|select(.|type=="object")|to_entries[].value' \
  helm-dependencies.yaml > /tmp/teks_ecr_containers.json

yq -rc '.dependencies|paths|select((length>2 and .[1]=="containers" and (.[-1]=="repository") or .[-2]=="name" and .[-1]=="image"))|".dependencies["+(.[0]|tostring)+"].containers[\""+(.[2:-2]|join("\"][\""))+"\"]"' \
  helm-dependencies.yaml | sed -r 's,\\",",g' > /tmp/teks_ecr_containers_paths.json

while read c; do
	echo "processing $c" >&2
  echo $(yq "${c}|${NAMESELECTOR}" helm-dependencies.yaml) $(yq "${c}.ver.tag" helm-dependencies.yaml) $c
done < /tmp/teks_ecr_containers_paths.json > /tmp/teks_ecr_containers_paths_eval.json

echo "extracted containers names and versions data:"
cat /tmp/teks_ecr_containers_paths_eval.json

for c in $(jq -r "\"docker://\" + ${NAMESELECTOR}" /tmp/teks_ecr_containers.json); do
  echo "fetching tags info for $c"
  tags=$(podman run --rm quay.io/skopeo/stable list-tags --tls-verify=true --authfile=/auth.json $c)
  # NOTE: omit/strip improperly formatted versions, like '1.2.3-foo' and 'latest', for loose sorting
  latest=$(jq -r '.Tags[] | select(.|test("^v?[0-9][0-9]*\\."))' <<< $tags | jq -Rn '[inputs]' | python -c "import io; import json; import sys; from packaging.version import parse as P; print(sorted(json.load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8')),key=P)[-1])")
  new_tag=$(jq -r '.Tags[]' <<< $tags | grep -E "^${latest}" | sort -h | head -1)
  repo=$(jq -r '.Repository' <<< $tags)

  matchlist=$(grep "${repo}" /tmp/teks_ecr_containers_paths_eval.json | awk '!/null/ {print $NF}')
  for match in $(echo $matchlist); do
    tag=$(yq "${match}.ver.tag" helm-dependencies.yaml)
    if [ -z "$match" ] || [ "$tag" = "null" ] || [ "$tag" = "$new_tag" ]; then
      echo "WARNING: nothing newest matched by $match" >&2
      continue
    fi

    patch=$(yq "${match}" helm-dependencies.yaml | sed -r "s/$tag/\"$new_tag\"/g")

    echo "updating ${repo}:${new_tag} from $tag in $match: $patch"
    yq "$match=$patch" helm-dependencies.yaml |\
      python -c "import io; import yaml; import sys; print(yaml.dump(yaml.safe_load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8').read())))" >\
      helm-dependencies_.yaml
    mv -f helm-dependencies_.yaml helm-dependencies.yaml
  done
done
