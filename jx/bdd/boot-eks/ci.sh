#!/usr/bin/env bash
set -e
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

gcloud auth activate-service-account --key-file $GKE_SA

# lets setup git 
git config --global --add user.name CJXDBot
git config --global --add user.email $GH_EMAIL

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
export JX_VALUE_PIPELINEUSER_GITHUB_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_GITHUB_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"


# override checking for diffs in jx-requirements.yaml as we need to change it before booting
export OVERRIDE_DIFF_CHECK="true"

export OVERRIDE_IRSA_IN_CLUSTER="true"

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
  sed -i "/^ *versionStream:/,/^ *[^:]*:/s/ref: .*/ref: ${PULL_PULL_SHA}/" ../jx/bdd/boot-gke/jx-requirements.yml
fi

echo "Using ../jx/bdd/boot-eks/jx-requirements.yml"
cat ../jx/bdd/boot-eks/jx-requirements.yml
cp ../jx/bdd/boot-eks/jx-requirements.yml .

helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

mkdir /workspace/source/reports
export REPORTS_DIR=/workspace/source/reports

export EKS_BDD_RUN=true

#install aws-iam-authenticator here as we don't want to add it to our base images
curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator && \
  chmod +x ./aws-iam-authenticator && \
  mv aws-iam-authenticator /usr/local/bin/

#just for BDD tests until we have CJXD V6
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/0.11.0/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
  mv /tmp/eksctl /usr/local/bin -f

jx step bdd \
    --use-revision \
    --version-repo-pr \
    --versions-repo https://github.com/cloudbees/cloudbees-jenkins-x-versions.git \
    --gopath /tmp \
    --git-provider=github \
    --config ../jx/bdd/boot-eks/cluster.yaml \
    --git-username $GH_USERNAME \
    --test-git-repo=https://github.com/dgozalo/bdd-jx.git \
    --test-git-branch=feature/disable_jenkins-x_file_import_for_EKS \
    --git-owner $GH_OWNER \
    --git-api-token $GH_ACCESS_TOKEN \
    --default-admin-password $JENKINS_PASSWORD \
    --no-delete-app \
    --no-delete-repo \
    --tests install \
    --tests test-verify-pods \
    --tests test-create-spring \
    --tests test-quickstart-golang-http \
    --tests test-import-node-http
