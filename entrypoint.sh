#!/bin/bash

KUSTOMIZATION_DIR_LOCATION="./"
BRANCH_NAME_TO_COMPARE="master"
KUSTOMIZE_TEMP_FOLDER=kustomize_build_temp

echo "  ┌───────"
if [ -n "$1" ]; then KUSTOMIZATION_DIR_LOCATION="$1"; else echo "  ├ WARNING No kustomization directory path specified, using current working directory";fi
if [ -n "$2" ]; then BRANCH_NAME_TO_COMPARE="$2"; else echo "  ├ WARNING No compare branch specified, using local ${BRANCH_NAME_TO_COMPARE} as default"; fi
if [[ -f "$KUSTOMIZATION_DIR_LOCATION" ]] || [ ! -z "$(cd "${KUSTOMIZATION_DIR_LOCATION}" 2>&1)" ]; then  echo "  └ ERROR the kustomization directory path $(pwd)/$KUSTOMIZATION_DIR_LOCATION does not exist"; exit 1; fi

cd "${KUSTOMIZATION_DIR_LOCATION}"

GIT_TOP_LEVEL_FOLDER=$(git rev-parse --show-toplevel)
KUSTOMIZATION_DIR_RELATIVE_PATH="$(pwd| sed s+"${GIT_TOP_LEVEL_FOLDER}"/++g)"
CURRENT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
BRANCHED_OFF_HASH=$(git merge-base "${CURRENT_BRANCH_NAME}" "${BRANCH_NAME_TO_COMPARE}")

echo "  ├ Comparing kustomize builds $KUSTOMIZATION_DIR_LOCATION kustomization.yaml "
echo "  ├ FROM new ${CURRENT_BRANCH_NAME}"
echo "  ├   TO old ${BRANCH_NAME_TO_COMPARE} branched off commit ${BRANCHED_OFF_HASH}"

mkdir -p "${KUSTOMIZE_TEMP_FOLDER}"
kustomize_build_new=$(kustomize build . 2>&1 > "${KUSTOMIZE_TEMP_FOLDER}"/kustomize-new.yaml)
if [ ! -z "$kustomize_build_new" ]; then
  echo "  ├ ERROR kustomize build failed for current changes"
  while IFS= read -r line ; do echo "  ├ $line"; done <<< "$kustomize_build_new"
  if [ -d "${KUSTOMIZE_TEMP_FOLDER}" ]; then rm -Rf "${KUSTOMIZE_TEMP_FOLDER}"; fi
  exit 1
fi

cd "${KUSTOMIZE_TEMP_FOLDER}"

detached_folder="${BRANCH_NAME_TO_COMPARE}-detached"
if [ -d "$detached_folder" ]; then rm -Rf $detached_folder; fi
git worktree prune
detaching_git_worktree=$(git worktree add ${detached_folder} --checkout --detach "${BRANCH_NAME_TO_COMPARE}") || exit 1
while IFS= read -r line ; do echo "  ├ $line"; done <<< "$detaching_git_worktree"
cd "${detached_folder}"

# check if same directory exists in other branch
if [[ -f "$KUSTOMIZATION_DIR_RELATIVE_PATH" ]] || [ ! -z "$(cd "${KUSTOMIZATION_DIR_RELATIVE_PATH}" 2>&1)" ]
then
  echo "  └ ERROR branch $BRANCH_NAME_TO_COMPARE does not have $KUSTOMIZATION_DIR_RELATIVE_PATH, cannot compare branches"
  if [ -d "${KUSTOMIZE_TEMP_FOLDER}" ]; then rm -Rf "${KUSTOMIZE_TEMP_FOLDER}"; fi
  exit 1
fi
cd "${KUSTOMIZATION_DIR_RELATIVE_PATH}"
checkout_branched_off_hash=$(git checkout "${BRANCHED_OFF_HASH}" 2>&1) || exit 1
while IFS= read -r line ; do echo "  ├─ $line"; done <<< "$checkout_branched_off_hash"


kustomize_build_old=$(kustomize build . 2>&1 > "${GIT_TOP_LEVEL_FOLDER}/${KUSTOMIZATION_DIR_RELATIVE_PATH}/"${KUSTOMIZE_TEMP_FOLDER}"/kustomize-old.yaml")
if [ ! -z "$kustomize_build_old" ]; then
  echo "  └ ERROR kustomize build failed for $BRANCH_NAME_TO_COMPARE"
  while IFS= read -r line ; do echo "  ├ $line"; done <<< "$kustomize_build_old"
  cd "${GIT_TOP_LEVEL_FOLDER}/${KUSTOMIZATION_DIR_RELATIVE_PATH}"
  if [ -d "${KUSTOMIZE_TEMP_FOLDER}" ]; then rm -Rf "${KUSTOMIZE_TEMP_FOLDER}"; fi
  exit 1
fi

cd "${GIT_TOP_LEVEL_FOLDER}/${KUSTOMIZATION_DIR_RELATIVE_PATH}/${KUSTOMIZE_TEMP_FOLDER}"
git worktree prune
if [ -d "$detached_folder" ]; then rm -Rf $detached_folder; fi

echo "  ├ Splitting kustomization build into separate objects"

cat kustomize-new.yaml | csplit - -f 'new.' -b '%03d.yaml' -k /^---$/ '{*}' > /dev/null
cat kustomize-old.yaml | csplit - -f 'old.' -b '%03d.yaml' -k /^---$/ '{*}' > /dev/null
echo "  └ Processing diff"

generated_files=$(ls | grep -E ".*[0-9]+\.yaml$")
file_prefix_to_diff=""

for file in $generated_files
do
  version="new"
  if [[ $file == *"old"* ]]; then version="old"; fi
  apiVersion=$(yq r $file apiVersion | sed "s+/+"W"+g")
  kind=$(yq r $file kind)
  name=$(yq r $file metadata.name)
  ns=$(yq r $file metadata.namespace)

  if [ -z "$ns" ]; then
    if [ "$kind" == "Namespace" ]; then
      ns="$name"
    else
      ns="default"
    fi
  fi
  new_file_name="${ns}_${kind}_${name}_${apiVersion}"
  if [[ $file_prefix_to_diff != *"$new_file_name"* ]]; then file_prefix_to_diff="${file_prefix_to_diff} $new_file_name"; fi
  mv "$file" "${new_file_name}_${version}.yaml"
done

function prettyPrintFileName {
  IFS='_' read -ra ADDR <<< "$1"
  echo "│ apiVersion: $( echo ${ADDR[3]} | sed s+W+/+g)"
  echo "│ kind: ${ADDR[1]}"
  echo "│ metadata:"
  echo "│   name: ${ADDR[2]}"
  echo "│   namespace: ${ADDR[0]}"
}

changes_detected=false
for file_prefix in ${file_prefix_to_diff}
do
  [ ! -f "${file_prefix}_old.yaml" ] && changes_detected=true && printf "\n╭─ + NEW OBJECT\n$(prettyPrintFileName "$file_prefix")\n╰──────────\n\n"
  [ ! -f "${file_prefix}_new.yaml" ] && changes_detected=true && printf "\n╭─ - DELETED OBJECT\n$(prettyPrintFileName "$file_prefix")\n╰──────────\n\n"
  if [ -f "${file_prefix}_old.yaml" ] && [ -f "${file_prefix}_new.yaml" ]; then
    diff_result=$(git diff --no-prefix --no-index "${file_prefix}_old.yaml" "${file_prefix}_new.yaml" | tail -n +5)
    if [ ! -z "$diff_result" ]; then
      changes_detected=true
      printf "\n╭─ * UPDATED OBJECT \n$(prettyPrintFileName "$file_prefix")\n╰─┬─────────\n"
      while IFS= read -r line ; do echo "  │ $line"; done <<< "$diff_result"
      echo "  ╰──────────"
    fi
  fi
done
if [ "$changes_detected" = false ] ; then
  echo "  ╭─"
  echo "  │ No changes detected for ${KUSTOMIZATION_DIR_RELATIVE_PATH}/kustomization.yaml"
  echo "  ╰─"

fi

cd "${GIT_TOP_LEVEL_FOLDER}/${KUSTOMIZATION_DIR_RELATIVE_PATH}"
if [ -d "${KUSTOMIZE_TEMP_FOLDER}" ]; then rm -Rf "${KUSTOMIZE_TEMP_FOLDER}"; fi