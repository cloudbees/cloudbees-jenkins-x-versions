#!/usr/bin/env bash
set -euo pipefail
set -x

export GH_USERNAME="jenkins-x-bot-test"
export GH_OWNER="cb-kubecd"
export GH_EMAIL="jenkins-x@googlegroups.com"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

JX_HOME="/tmp/jxhome"
KUBECONFIG="/tmp/jxhome/config"

mkdir -p $JX_HOME

jx --version
jx step git credentials

# setup GCP service account
gcloud auth activate-service-account --key-file $GKE_SA

# setup git 
git config --global --add user.name JenkinsXBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_PASSWORD"
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_EMAIL="$GH_EMAIL"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"

jx profile cloudbees

# prepare the BDD configuration
git clone https://github.com/cloudbees/cloudbees-jenkins-x-boot-config boot-source
cp jx/bdd/boot-gke-vault/jx-requirements.yml boot-source
cp jx/bdd/boot-gke-vault/parameters.yaml boot-source/env
cd boot-source

# Rotate the domain to avoid cert-manager API rate limit
if [[ "${DOMAIN_ROTATION}" == "true" ]]; then
    SHARD=$(date +"%l" | xargs)
    DOMAIN="${DOMAIN_PREFIX}${SHARD}${DOMAIN_SUFFIX}"
    if [[ -z "${DOMAIN}" ]]; then
        echo "Domain rotation enabled. Please set DOMAIN_PREFIX and DOMAIN_SUFFIX environment variables" 
        exit -1
    fi
    echo "Using domain: ${DOMAIN}"
    sed -i "/^ *ingress:/,/^ *[^:]*:/s/domain: .*/domain: ${DOMAIN}/" jx-requirements.yml
fi
echo "Using jx-requirements.yml"
cat jx-requirements.yml

# TODO hack until we fix boot to do this too!
helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

jx step bdd \
    --use-revision \
    --version-repo-pr \
    --versions-repo https://github.com/cloudbees/cloudbees-jenkins-x-versions.git \
    --config ../jx/bdd/boot-gke-vault/cluster.yaml \
    --gopath /tmp \
    --git-provider=github \
    --git-username $GH_USERNAME \
    --git-owner $GH_OWNER \
    --git-api-token $GH_ACCESS_TOKEN \
    --default-admin-password $JENKINS_PASSWORD \
    --no-delete-app \
    --no-delete-repo \
    --tests install \
    --tests test-verify-pods \
    --tests test-create-spring \
    --tests test-supported-quickstarts \
    --tests test-app-lifecycle
    # --tests test-import # fails with vault
