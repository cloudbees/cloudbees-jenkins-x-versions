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

# activate the GCP service account before uploading the report
gcloud auth activate-service-account --key-file $GKE_SA

touch /workspace/source/reports/bdd_boot_eks_report.html

jx step stash \
    -c tests \
    --basedir "${BASEDIR}" \
    -p "${REPORT}" \
    --bucket-url gs://cjxd-release-logs \
    -t "reports/${DATE}"
