#!/usr/bin/env bash

set -xeo pipefail
# This script is executed as part of helm install/upgrade job
# These are additional halyard config applied before deploying spinnaker

_SPINNAKER_NS="$1"
_OAUTH2_ENABLED="$2"
_OAUTH2_CLIENT_ID="$3"
_OAUTH2_CLIENT_SECRET="$4"

HALYARD_POD=$(kubectl -n ${_SPINNAKER_NS}  get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}")

# Enable debug for oauth2 and docker registry related code
kubectl -n ${_SPINNAKER_NS} exec $HALYARD_POD -- bash -c "
set -xeo pipefail;

mkdir -p ~/.hal/default/profiles;
cat << EOF_PROFILE > ~/.hal/default/profiles/spinnaker-local.yml;
logging:
  level:
    com.netflix.spinnaker.gate.security: DEBUG
    com.netflix.spinnaker.clouddriver.docker: DEBUG
EOF_PROFILE
"

# Config google oauth
if [[ "${_OAUTH2_ENABLED}" == "true" ]]; then
    $HAL_COMMAND config security api edit --override-base-url http://localhost:8084/

    $HAL_COMMAND config security authn oauth2 edit \
      --client-id ${_OAUTH2_CLIENT_ID} \
      --client-secret ${_OAUTH2_CLIENT_SECRET} \
      --provider google \
      --pre-established-redirect-uri http://localhost:8084/login

    $HAL_COMMAND config security authn oauth2 enable
fi
