#!/bin/bash

# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

DIR=$(dirname $0)
DOTENV=$1
ENV_FILE="$DIR/${DOTENV:-.env}"
BASE="$DIR/base"
KOVERLAY="$DIR/overlay"

# echo to stderr
echoerr() { echo "$@" 1>&2; }

# establish env
if [ ! -f "$ENV_FILE" ]; then
  echoerr "WARN: Configuration $ENV_FILE file does not exist"
else
  echoerr "Source env from $ENV_FILE"
  source ${ENV_FILE}
fi

# validate
if [ -z "$OCIR_REPO" ]; then
  echoerr "ERROR: Requires 'OCIR_REPO' variable ex: 'iad.ocir.io/mytenancy/my-repository'"
  exit 1
fi
if [ -z "$UNREAL_IMAGE_NAME" ]; then
  echoerr "ERROR: Requires 'UNREAL_IMAGE_NAME' variable ex: 'pixeldemo'"
  exit 1
fi

# warnings
if [ -z "$INGRESS_HOST" ]; then
  echoerr "WARN: Recommended 'INGRESS_HOST' variable ex: 'pixeldemo.yyy.yyy.yy.yyy.nip.io'"
fi
if [ -z "$NAMESPACE" ]; then
  echoerr "WARN: Recommended setting 'NAMESPACE' variable (default: pixel)"
fi
if [ -z "$OCIR_SECRET" ]; then
  echoerr "WARN: Using without 'OCIR_SECRET' private registry imagePullSecret ex: 'ocirsecret'"
fi

# Generate kustom overlay
echoerr "Generate kustomization overlay: $KOVERLAY/"
mkdir -p $KOVERLAY
cd $KOVERLAY

# Generate patches
echoerr "Generate patches..."

# patch the proxy service configuration
cat <<EOF > patch-proxy-configmap.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

apiVersion: v1
kind: ConfigMap
metadata:
  name: routing-pod-proxy-config
data:
  enable: "${PROXY_ENABLE:-false}"
  # specify the proxy router prefix
  path.prefix: "${PROXY_PATH_PREFIX:-/proxy}"
  # specify comma-separated basic auth users
  auth.users: "${PROXY_AUTH_USERS}"
EOF

# patch the turn credentials
cat <<EOF > patch-turn-credential.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

apiVersion: v1
kind: Secret
metadata:
  name: turn-secret
data:
  username: $(printf "${TURN_USER:-turnuser}" | base64)
  password: $(printf "${TURN_PASS:-turnpass}" | base64)
EOF

# patch ingress settings
cat <<EOF > patch-ingress-host.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

- op: replace
  path: /spec/tls/0/hosts/0
  value: ${INGRESS_HOST:-pixeldemo.lb-ip-addr.nip.io}
- op: replace
  path: /spec/rules/0/host
  value: ${INGRESS_HOST:-pixeldemo.lb-ip-addr.nip.io}
EOF

# create registry secret patches
if [ -n "$OCIR_SECRET" ]; then

cat <<EOF > patch-registry-secret.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

- op: add
  path: /spec/template/spec/imagePullSecrets
  value:
    - name: "${OCIR_SECRET}"
EOF
  # inject into the patchesJson6902
  PATCH_IMAGE_PULLS_SECRETS="
  # patch image registry secrets
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: DaemonSet
      name: turn
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: turn-api
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: stream
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: matchmaker
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: player
  - path: patch-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: podproxy
"
fi

# Generate overlay
echoerr "Generate kustomization.yaml..."
cat <<EOF > kustomization.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

# Auto-generated kustomization overlay from ${0}
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE:-pixel}

# extend base
bases:
  - "../base/"

# patches
patchesStrategicMerge:
  # patch the proxy configmap
  - patch-proxy-configmap.yaml
  # patch the turn username/password
  - patch-turn-credential.yaml

patchesJson6902:
  ${PATCH_IMAGE_PULLS_SECRETS}
  # patch the ingress hostname
  - path: patch-ingress-host.yaml
    target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: pixelstream-ingress

images:
  # pixel streaming runtime
  - name: pixelstreaming
    newName: ${OCIR_REPO}/${UNREAL_IMAGE_NAME}
    newTag: ${UNREAL_IMAGE_VERSION:-latest}

  # turn image
  - name: turn
    newName: ${OCIR_REPO}/turn
    newTag: ${IMAGE_TAG:-latest}

  # turn aggregator/discovery
  - name: turn-api
    newName: ${OCIR_REPO}/turn-api
    newTag: ${IMAGE_TAG:-latest}

  # signal server
  - name: signalserver
    newName: ${OCIR_REPO}/signalserver
    newTag: ${IMAGE_TAG:-latest}

  # matchmaker
  - name: matchmaker
    newName: ${OCIR_REPO}/matchmaker
    newTag: ${IMAGE_TAG:-latest}

  # player webview
  - name: player
    newName: ${OCIR_REPO}/player
    newTag: ${IMAGE_TAG:-latest}

  # dynamic proxy svc
  - name: podproxy
    newName: ${OCIR_REPO}/podproxy
    newTag: ${IMAGE_TAG:-latest}

  # operator tools (kubectl, docker, jq)
  - name: kubetools
    newName: ${OCIR_REPO}/kubetools
    newTag: ${IMAGE_TAG:-latest}
EOF

echoerr "Exec 'kubectl kustomize' from $KOVERLAY/kustomization.yaml"
echoerr "---"
kubectl kustomize .