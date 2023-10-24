#!/bin/bash
# Fetch containers images data from helm-dependencies.yaml and update tags info
# Requires: jq, yq, pyyaml, podman; pypi: packaging
# Examples:
#  # updates containers tags info to the recommended versions (Helm specific),
#  # or take the most recent versions, when no such data could be discovered.
#  ./update_containers_tags.sh -a
#
#  ./update_containers_tags.sh -a --recent # update all versions to the most recent tags
#  ./update_containers_tags.sh -n dex # update containers versions for dex only
#  ./update_containers_tags.sh -i webhook # update all webhooks containers tags, consider AppVesions, if any discoverable
#  ./update_containers_tags.sh --recent -i public.ecr.aws/eks/aws-load-balancer-controller # prefer most recent tag over AppVersion
#  ./update_containers_tags.sh -n 'foo|bar' -i 'public.ecr|k8s.gcr' # a multi-select example, by addons names and images registries

usage(){
  cat << EOF
  Usage:
    -h - print this usage info
    -a - update all containers versions information
         in helm-dependencies.yaml.
    --recent - ignore version tags recommended by Helm charts
         AppVersion, prefer most recent tags intead.
    -n X - match images by an addon name pattern.
    -i Y - match images by a given name pattern
         (imageRegistry/imageNamespace/imageName).
EOF
}

mode=auto # consider AppVersion info, whenever discoverable
all=unset # update tags for all containers
scoped=unset

[[ "$#" = "0" ]] && usage >&2 && exit 1
while (( $# )); do
  case "$1" in
    '-h') usage >&2; exit 1 ;;
    '-i') shift; scoped=true; i="${1}" ;;
    '-n') shift; scoped=true; n="${1}" ;;
    '--recent') mode=recent ;;
    '-a') all=true; i=".*"; n=".*" ;;
    *) usage >&2; exit 22;;
  esac
  shift
done

if [ "$all" = "true" ] && [ "$scoped" = "true" ]; then
  echo "ERROR - cannot use -a with other options but --recent"
  usage >&2; exit 22
fi

# Update JSONpath ($1) containing tag ($2) with a new tag ($3) in helm-dependencies.yaml,
# for image ($3), and chart ($4) (may be null, i.e. not managed by Helm)
function update() {
  local json_path=$1
  local tag=$2
  local new_tag=$3
  local image=$4
  local chart=$5
  local rc=1
  local new_tag
  local patch
  # tag could be "v?$app_version", so we need to pick a real one from the list of tags fetched with skopeo
  new_tag=$(jq -r '.Tags[]' <<< $TAGS | grep -E -m1 "^v?${new_tag}$")
  grep -q "${new_tag}$" <<< $tag  # FIXME: reject downgrades, at least for mode=recent?
  if [ $? -eq 0 ]; then
    echo "INFO - $image: no updates available for $new_tag (chart=$chart)"
    echo "$chart $image $json_path" >> /tmp/teks_ecr_containers_patched_images.txt
    return 0
  fi

  echo "INFO - $image: updating image tag ${tag} to $new_tag (chart=$chart)"
  patch=$(yq -c "$json_path" helm-dependencies.yaml | sed -r "s/\b${tag}\b/$new_tag/g")
  yq -eS "$json_path=$patch" helm-dependencies.yaml |\
    python -c "import io; import yaml; import sys; print(yaml.dump(yaml.safe_load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8').read()), sort_keys=True))" >\
    helm-dependencies_.yaml
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "DEBUG - $image: patched image tag (chart=$chart) at JSONpath: $json_path, with $patch"
    mv -f helm-dependencies_.yaml helm-dependencies.yaml
    echo "$chart $image $json_path" >> /tmp/teks_ecr_containers_patched_images.txt
  else
    echo "ERROR: - $image: failed patching image tag (chart=$chart) at JSONpath: $json_path with $patch"
  fi
  return $rc
}

if ! test -f helm-dependencies.yaml ; then
  echo "CRITICAL - No such file helm-dependencies.yaml"
  exit 2
fi

NAMESELECTOR='if .registry? then "\(.registry.registry)/" else "" end + if .name.image? then .name.image else .name.repository end'

yq ".dependencies[]|select(.containers?)|select(.name|test(\"$n\"))[]|select(.|type==\"object\")|to_entries[].value|select(((.registry.registry?) and (.registry.registry|test(\"$i\"))) or ((.name.repository?) and (.name.repository|test(\"$i\"))) or ((.name.image?) and (.name.image|test(\"$i\"))))" helm-dependencies.yaml \
  > /tmp/teks_ecr_containers.json
if [ $? -ne 0 ]; then
  echo "CRITICAL - unexpcted data inputs in helm-dependencies.yaml"
  exit 61
fi

yq -rc '.dependencies|paths|select((length>2 and .[1]=="containers" and (.[-1]=="repository") or .[-2]=="name" and .[-1]=="image"))|".dependencies["+(.[0]|tostring)+"].containers[\""+(.[2:-2]|join("\"][\""))+"\"]"' \
  helm-dependencies.yaml | sed -r 's,\\",",g' > /tmp/teks_ecr_containers_paths.json

if [ -z "$(cat /tmp/teks_ecr_containers.json)" ]; then
  echo "CRTICAL - No containers images have been selected for updates"
  exit 61
fi

echo "DEBUG - evaluating all containers images JSONpaths defined in helm-dependencies.yaml"
# produce data fields: chart image tag JSONpath for the selected images
while read c; do
	echo "DEBUG - processing data for $c" >&2
  echo $(yq -r "${c}.chart" helm-dependencies.yaml) $(yq -r "${c}|${NAMESELECTOR}" helm-dependencies.yaml) $(yq -r "${c}.ver.tag" helm-dependencies.yaml) $c
done < /tmp/teks_ecr_containers_paths.json > /tmp/teks_ecr_containers_paths_eval.txt
echo "DEBUG - extracted data for containers images: Helm Chart Owner, Image, Version, JSONpath"

rm -f /tmp/teks_ecr_containers_patched_images.txt
touch /tmp/teks_ecr_containers_patched_images.txt
while read chart image; do
  if [ "$chart" = "null" ]; then
    type="not managed by Helm"
  else
    type=$chart
  fi

  app_version=null
  c="docker://${image}"
  # we always need the list of actual tags for future checks
  echo "DEBUG - $image: fetching tags info with skopeo"
  TAGS=$(podman run --rm quay.io/skopeo/stable list-tags --tls-verify=true --authfile=/auth.json $c 2>/dev/null)

  # skip updating matched images, when it contains unrelated Helm charts data (leave them out for the next iterations)
  matchlist=$(grep " $image " /tmp/teks_ecr_containers_paths_eval.txt | grep -E "^(null|$chart) " | awk '!/ null/ {print $NF}')
  if [ -z "$matchlist" ]; then
    echo "ERROR - $image: (type) unexpected error: no image data matched"
    continue
  fi

  # iterate matched images' within the chart scope, or not managed by helm (chart is null)
  for json_path in $(echo $matchlist); do
    grep -qF "$chart $image $json_path" /tmp/teks_ecr_containers_patched_images.txt
    if [ $? -eq 0 ]; then
      echo "DEBUG - $image: ($type) skipping already updated image at $json_path"
      continue
    fi

    echo "DEBUG - $image: processing data: chart=$chart tag=$tag JSONpath=$json_path"
    tag=$(yq -r "${json_path}.ver.tag" helm-dependencies.yaml)
    if [ "$chart" != "null" ] && [ "$mode" != "recent" ]; then
      # FIXME: lookup the namespace from the current cluster context, by searching for the addon's helm release secret.
      # Only fallback to ns specified in helm-dependencies in case of a greenfield deloyment.
      namespace=$(yq -r ".dependencies[]|select(.name==\"${chart}\").namespace" helm-dependencies.yaml)
      helm_repo=$(yq -r ".dependencies[]|select(.name==\"${chart}\").repository" helm-dependencies.yaml)
      helm_release=$(yq -r ".dependencies[]|select(.name==\"${chart}\").version" helm-dependencies.yaml)
      echo "DEBUG - $image: ensuring local Helm repo $helm_repo for chart $chart"
      helm repo add ${chart} ${helm_repo} > /dev/null
      echo "DEBUG - $image: ($type) discovering AppVersion from Helm release $helm_release"
      app_version=$(helm search repo ${chart}/${chart} --version ${helm_release} -n ${namespace} -o json | jq -er '.[0].app_version' || echo null)
      if [ "$app_version" != "null" ]; then
        update $json_path $tag $app_version $image $chart
        continue
      fi
      echo "WARNING - $image: ($type) couldn't discover AppVersion from Helm release $helm_release: fetching a recent tag for it instead"
    fi

    # omit/strip improperly formatted versions, like '1.2.3-foo' and 'latest', for loose sorting
    echo "DEBUG - $image: ($type) getting the most recent tag value"
    latest=$(jq -r '.Tags[] | select(.|test("^v?[0-9][0-9]*\\."))' <<< $TAGS | jq -Rn '[inputs]' | python -c "import io; import json; import sys; from packaging.version import parse as P; print(sorted(json.load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8')),key=P)[-1])")
    if [ -z "$latest" ]; then
      echo "FATAL - $image: unexpected error fetching latest tags info, stopping"
      exit 1
    fi
    update $json_path $tag $latest $image $chart
  done # next json_path from matchlist
done < <(jq -r "\"\(.chart) \(${NAMESELECTOR})\"" /tmp/teks_ecr_containers.json)
