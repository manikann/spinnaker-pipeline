#!/usr/bin/env bash

# This script is copied to halyard pod by helm install script (install-spinnaker.sh)
# Invoked by register-app cloudbuild (register-app.sh), to configure halyard with application details (docker-registry and  kubeconfig)

set -eo pipefail


function configFile() {
  mkdir -p /home/spinnaker/.hal/app-config
  #mktemp /home/spinnaker/.hal/app-config/${1}.XXXXX
  echo /home/spinnaker/.hal/app-config/${1}
}

function echoAndExec() {
  echo "$@"
  eval "$@"
}

function getDataFromSecret() {
  local secretName=$1
  local key=$(echo "$2" | sed 's/\./\\./g')
  kubectl get secret $secretName -o=jsonpath="{.data.${key}}" | base64 --decode
}

function getLabelFromSecret() {
  local secretName=$1
  local key=$(echo "$2" | sed 's/\./\\./g')
  kubectl get secret $secretName -o=jsonpath="{.metadata.labels.${key}}"
}

function getCommandForAccount() {
  local accountType=$1
  local accountName=$2

  if hal config provider "$accountType" account get "$accountName" >/dev/null 2>&1; then
    echo "edit"
  else
    echo "add"
  fi
}

function getCommandForArtifactAccount() {
  local accountType=$1
  local accountName=$2

  if hal config artifact "$accountType" account get "$accountName" >/dev/null 2>&1; then
    echo "edit"
  else
    echo "add"
  fi
}
function configureDockerRegistryAccount() {
  local configName=$1
  local server=$(getDataFromSecret $configName "server")
  local email=$(getDataFromSecret $configName "email")
  local bucket=$(getDataFromSecret $configName "bucket")

  local repositories=$(getDataFromSecret $configName "repositories")
  local repo_param=""
  if [[ ! -z "$repositories" ]]; then
    repo_param="--repositories $repositories"
  fi

  local passwordFile=$(configFile ${configName}.password)
  getDataFromSecret $configName "password" | tr -d '\n' > $passwordFile

  echoAndExec hal config provider docker-registry account \
        $(getCommandForAccount docker-registry "$configName") \
        "$configName" \
        --address "$server" \
        --username "_json_key" \
        --email "$email" \
        --password-file $passwordFile $repo_param

  if [[ ! -z "$bucket" ]]; then
    local accountName=$(echo "$bucket" | sed 's/gs:\/\///' | tr -s '[:punct:]' '-')
    echoAndExec hal config artifact gcs account \
          $(getCommandForArtifactAccount gcs "$accountName") \
          "$accountName" \
          --json-path $passwordFile
    echoAndExec hal config artifact gcs enable
  fi
}

function processDockerRegistryAccounts() {
  if local secretList=$(kubectl get secret --selector paas.ex.anz.com/type=dockerconfigjson -o=jsonpath='{.items[*].metadata.name}'); then
    for aSecret in $secretList; do
      echo "Processing docker-registry account '$aSecret'"
      configureDockerRegistryAccount $aSecret
    done
  fi
}

function configureKubernetesAccount() {
  local configName=$1

  local appClusterName=$(getLabelFromSecret $configName "paas.ex.anz.com/cluster")
  local appProjectId=$(getLabelFromSecret $configName "paas.ex.anz.com/project")
  local registries=$(kubectl get secret --selector paas.ex.anz.com/type=dockerconfigjson,paas.ex.anz.com/cluster=$appClusterName -o=jsonpath='{.items[*].metadata.name}' \
                        | tr -s '[:blank:][:space:]' ',,')
  local reg_param=""
  if [[ ! -z "$registries" ]]; then
    reg_param="--docker-registries $registries"
  fi

  local kubeconfigFile=$(configFile ${appProjectId}-${appClusterName}.kubeconfig)
  getDataFromSecret $configName "kubeconfig" > $kubeconfigFile

  if local context_list=$(kubectl --kubeconfig $kubeconfigFile config get-contexts -o=name); then
    for context in $context_list; do
      local account_name="$(echo "${appProjectId}-${appClusterName}-${context}" | tr -s '[:punct:]' '-')"
      echo "Creating kubernetes account '$account_name'"
      echoAndExec hal config provider kubernetes account \
                $(getCommandForAccount kubernetes "$account_name") \
                "$account_name" \
                --context "$context" \
                --kubeconfig-file $kubeconfigFile \
                --namespaces "$context" \
                --provider-version v2 $reg_param
    done
  fi
}

function processKubernetesAccounts() {
  if local secretList=$(kubectl get secret --selector paas.ex.anz.com/type=kubeconfig -o=jsonpath='{.items[*].metadata.name}'); then
    for aSecret in $secretList; do
      echo "Processing kubernetes account '$aSecret'"
      configureKubernetesAccount $aSecret
    done
  fi
}

processDockerRegistryAccounts
processKubernetesAccounts

# Apply  the config changes
hal config
hal deploy apply
