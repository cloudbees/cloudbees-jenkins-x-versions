#!/usr/bin/env bash
set -euo pipefail
set -x

export GH_USERNAME="cjxd-bot-test"
export GH_OWNER="cb-kubecd"
export GH_EMAIL="jenkins-x@googlegroups.com"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

JX_HOME="/tmp/jxhome"
KUBECONFIG="/tmp/jxhome/config"

# lets avoid the git/credentials causing confusion during the test
export XDG_CONFIG_HOME=$JX_HOME

mkdir -p $JX_HOME/git

# replace the credentials file with a single user entry
echo "https://$GH_USERNAME:$GH_ACCESS_TOKEN@github.com" > $JX_HOME/git/credentials

# setup GCP service account
gcloud auth activate-service-account --key-file $GKE_SA

# setup git 
git config --global --add user.name CJXDBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_REQUIREMENT_ENV_GIT_PUBLIC=true
export JX_REQUIREMENT_GIT_PUBLIC=true
export JX_REQUIREMENT_ENV_GIT_OWNER="$GH_OWNER"
export JX_REQUIREMENT_PROJECT="jenkins-x-bdd3"
export JX_REQUIREMENT_ZONE="europe-west1-c"
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_PASSWORD"
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_EMAIL="$GH_EMAIL"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"


mkdir boot-source
cd boot-source

JX_DOWNLOAD_LOCATION=$(<../jx/CJXD_LOCATION_LINUX)

wget $JX_DOWNLOAD_LOCATION
tar -zxvf jx-linux-amd64.tar.gz
export PATH=$(pwd):$PATH

jx install dependencies --all

jx --version


# use the current git SHA being built in the version stream
if [[ -n "${PULL_PULL_SHA}" ]]; then
  sed -i "/^ *versionStream:/,/^ *[^:]*:/s/ref: .*/ref: ${PULL_PULL_SHA}/" ../jx/bdd/boot-gke-vault/jx-requirements.yml
fi


# Rotate the domain to avoid cert-manager API rate limit and collisions by combining minute and day of year to generate
# a number between 1 and 12 that will effectively rotate every 12 minutes from a different starting point every 12 days.
if [[ "${DOMAIN_ROTATION}" == "true" ]]; then
    MIN=$(date +"%-M" | xargs)
    DOY=$(date +"%-j" | xargs)
    SHARD=$(((MIN + DOY) % 12))
    # If we end up at 0, then roll back over to 12.
    if [[ $SHARD -eq 0 ]]; then
        SHARD=12
    fi
    DOMAIN="${DOMAIN_PREFIX}${SHARD}${DOMAIN_SUFFIX}"
    if [[ -z "${DOMAIN}" ]]; then
        echo "Domain rotation enabled. Please set DOMAIN_PREFIX and DOMAIN_SUFFIX environment variables" 
        exit -1
    fi
    echo "Using domain: ${DOMAIN}"
    sed -i "/^ *ingress:/,/^ *[^:]*:/s/domain: .*/domain: ${DOMAIN}/" ../jx/bdd/boot-gke-vault/jx-requirements.yml
fi

echo "Using ../jx/bdd/boot-gke-vault/jx-requirements.yml"
cat ../jx/bdd/boot-gke-vault/jx-requirements.yml



cp ../jx/bdd/boot-gke-vault/jx-requirements.yml .

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
    --tests test-quickstart-node-http
    # --tests test-import # fails with vault
