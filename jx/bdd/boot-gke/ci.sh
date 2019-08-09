#!/usr/bin/env bash
set -e
set -x

export GH_USERNAME="jenkins-x-bot-test"
export GH_OWNER="cb-kubecd"

export GH_CREDS_PSW="$(jx step credential -s jenkins-x-bot-test-github)"
export JENKINS_CREDS_PSW="$(jx step credential -s  test-jenkins-user)"
export GKE_SA="$(jx step credential -k bdd-credentials.json -s bdd-secret -f sa.json)"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

JX_HOME="/tmp/jxhome"
KUBECONFIG="/tmp/jxhome/config"

mkdir -p $JX_HOME

jx --version
jx step git credentials

gcloud auth activate-service-account --key-file $GKE_SA

# lets setup git 
git config --global --add user.name JenkinsXBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_CREDS_PSW"
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_GITHUB_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_GITHUB_TOKEN="$GH_CREDS_PSW"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_CREDS_PSW"
export JX_VALUE_PROW_HMACTOKEN="$GH_CREDS_PSW"

# override checking for diffs in jx-requirements.yaml as we need to change it before booting
export OVERRIDE_DIFF_CHECK="true"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"

jx profile cloudbees

git clone https://github.com/cloudbees/cloudbees-jenkins-x-boot-config boot-source
cp jx/bdd/boot-gke/jx-requirements.yml boot-source
cp jx/bdd/boot-gke/parameters.yaml boot-source/env
cd boot-source

helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

mkdir /workspace/source/reports
export REPORTS_DIR=/workspace/source/reports

jx step bdd \
    --use-revision \
    --version-repo-pr \
    --versions-repo https://github.com/cloudbees/cloudbees-jenkins-x-versions.git \
    --gopath /tmp --git-provider=github \
    --config ../jx/bdd/boot-gke/cluster.yaml \
    --git-username $GH_USERNAME \
    --git-owner $GH_OWNER \
    --git-api-token $GH_CREDS_PSW \
    --default-admin-password $JENKINS_CREDS_PSW \
    --no-delete-app \
    --no-delete-repo \
    --tests install \
    --tests test-verify-pods \
    --tests test-create-spring \
    --tests test-supported-quickstarts \
    --tests test-import \
    --tests test-devpod