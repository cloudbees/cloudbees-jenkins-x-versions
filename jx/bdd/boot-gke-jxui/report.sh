#!/usr/bin/env bash
set -euo pipefail
set -x

if [ $# -ne 2 ]; then
    echo "Please provide the base dir and report file"
    exit -1
fi
BASEDIR=$1
REPORT=$2
DATE=$(date '+%F')

echo "Generating test report"
jx step report junit --in-dir ${REPORT_IN_DIR} --merge --out-dir ${BASEDIR} --output-name ${REPORT_OUTPUT_NAME} --suite-name ${REPORT_SUITE_NAME}

# activate the GCP service account before uploading the report
gcloud auth activate-service-account --key-file $GKE_SA

echo "Uploading test report"
gsutil cp ${BASEDIR}/${REPORT} gs://cjxd-release-logs/reports/${DATE}/${VERSION}/

echo "Uploading test screenshots for failed tests"
gsutil cp -r ${BASEDIR}/screenshots/* gs://cjxd-release-logs/reports/${DATE}/${VERSION}/screenshots || true
