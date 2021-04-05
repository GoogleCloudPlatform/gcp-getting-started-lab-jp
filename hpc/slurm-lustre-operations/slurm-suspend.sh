#!/bin/bash
set -eu

cmdname=$( basename "$0" )

usage() {
  echo "Usage: ${cmdname} [-c config]" 1>&2
  echo "  -c : config file (default: slurm-01.yaml)" 1>&2
  exit 1
}

config="slurm-01.yaml"

while getopts c:h opt
do
  case $opt in
    "c" ) config="${OPTARG}" ;;
    "h" ) usage ;;
      * ) usage ;;
  esac
done

if [ ! -e "${config}" ]; then
  echo "Config file (${config}) is not found." 1>&2
  usage
fi

trimmed_config=$(sed -e 's| ||g' "${config}")
cluster=$(echo "${trimmed_config}" | grep cluster_name | sed -e 's|cluster_name:||g')
if [ "${cluster}" = "" ]; then
  echo "The cluster name is invalid."
  usage
fi
zone=$(echo "${trimmed_config}" | grep -m 1 zone | sed -e 's|zone:||g')
if [ "${zone}" = "" ]; then
  echo "The zone is invalid."
  usage
fi

instances=$( gcloud compute instances list --zones "${zone}" \
  --filter "name~${cluster}-compute" --format 'value(name)' )
if [ "${instances}" != "" ]; then
  gcloud compute instances delete ${instances} --zone "${zone}" --quiet
fi

mgmt=$( gcloud deployment-manager deployments describe "${cluster}" --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep -v image)
for id in ${mgmt}; do
  gcloud beta compute instances suspend "${id}" --zone "${zone}"
done
