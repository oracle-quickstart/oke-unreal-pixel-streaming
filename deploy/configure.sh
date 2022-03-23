#!/bin/bash

# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

DIR=$(dirname $0)
BASE_DIR="$DIR/base"
OVERLAY_DIR="$DIR/overlay"

# interpret env/properties arg
DOTENV=$1
ENV_FILE="${DOTENV:-$DIR/.env}"

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
if [ -z "$REPO" ]; then
  echoerr "ERROR: Requires 'REPO' variable ex: 'iad.ocir.io/mytenancy/my-repo'"
  exit 1
fi
if [ -z "$UNREAL_REPO" ]; then
  echoerr "ERROR: Requires 'UNREAL_REPO' variable ex: 'iad.ocir.io/mytenancy/my-unreal-repo'"
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
if [ -z "$REPO_SECRET" ]; then
  echoerr "WARN: Using without 'REPO_SECRET' private registry imagePullSecret ex: 'ocirsecret'"
fi
if [ -z "$UNREAL_REPO_SECRET" ]; then
  echoerr "WARN: Using without 'UNREAL_REPO_SECRET' private registry imagePullSecret ex: 'ocirsecret'"
fi

# Generate kustom overlay
echoerr "Generate kustomization overlay: $OVERLAY_DIR/"
mkdir -p $OVERLAY_DIR
cd $OVERLAY_DIR

# Generate patches
echoerr "Generate patches..."

# patch the proxy service configuration
cat <<EOF > patch-proxy-configmap.yaml
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

apiVersion: v1
kind: Secret
metadata:
  name: turn-secret
data:
  username: $(printf "${TURN_USER:-turnuser}" | base64)
  password: $(printf "${TURN_PASS:-turnpass}" | base64)
EOF

# patch ingress settings
if [ -n "$INGRESS_HOST" ]; then
cat <<EOF > patch-ingress.yaml
- op: add
  path: /spec/tls
  value: 
    - secretName: pixelstream-tls-secret
      hosts:
        - ${INGRESS_HOST}
- op: add
  path: /spec/rules/0/host
  value: ${INGRESS_HOST}
EOF

# consider alternate path prefix
if [ -n "$INGRESS_PATH" ]; then
cat << EOF >> patch-ingress.yaml
- op: replace
  path: /spec/rules/0/http/paths/0/path
  value: ${INGRESS_PATH}/(.*)
EOF
fi

# inject into the patchesJson6902
  PATCH_INGRESS="
  # patch the ingress hostname
  - path: patch-ingress.yaml
    target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: pixelstream-ingress
"
fi

# create registry secret patches
if [ -n "$REPO_SECRET" ]; then

cat <<EOF > patch-registry-secret.yaml
- op: add
  path: /spec/template/spec/imagePullSecrets/-
  value:
    name: "${REPO_SECRET}"
EOF
  # inject into the patchesJson6902
  PATCH_IMAGE_PULL_SECRET="
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

# create unreal registry secret patches
if [ -n "$UNREAL_REPO_SECRET" ]; then

cat <<EOF > patch-unreal-registry-secret.yaml
- op: add
  path: /spec/template/spec/imagePullSecrets/-
  value:
    name: "${UNREAL_REPO_SECRET}"
EOF
  # inject into the patchesJson6902
  PATCH_UNREAL_PULL_SECRET="
  # patch unreal image registry secret
  - path: patch-unreal-registry-secret.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: stream
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
  ${PATCH_IMAGE_PULL_SECRET}
  ${PATCH_UNREAL_PULL_SECRET}
  ${PATCH_INGRESS}

images:
  # pixel streaming application
  - name: pixelstreaming
    newName: ${UNREAL_REPO}/${UNREAL_IMAGE_NAME}
    newTag: ${UNREAL_IMAGE_TAG:-latest}

  # turn image
  - name: turn
    newName: ${REPO}/turn
    newTag: ${IMAGE_TAG:-latest}

  # turn aggregator/discovery
  - name: turn-api
    newName: ${REPO}/turn-api
    newTag: ${IMAGE_TAG:-latest}

  # signal server
  - name: signalserver
    newName: ${REPO}/signalserver
    newTag: ${IMAGE_TAG:-latest}

  # matchmaker
  - name: matchmaker
    newName: ${REPO}/matchmaker
    newTag: ${IMAGE_TAG:-latest}

  # player webview
  - name: player
    newName: ${REPO}/player
    newTag: ${IMAGE_TAG:-latest}

  # dynamic proxy svc
  - name: podproxy
    newName: ${REPO}/podproxy
    newTag: ${IMAGE_TAG:-latest}

  # operator tools (kubectl, docker, jq)
  - name: kubetools
    newName: ${REPO}/kubetools
    newTag: ${IMAGE_TAG:-latest}
EOF

echoerr "Exec 'kubectl kustomize' from $OVERLAY_DIR/kustomization.yaml"
echoerr "---"
kubectl kustomize .