#!/bin/sh
set -eu

cmdname=$( basename "$0" )

usage() {
  echo "Usage: ${cmdname} [-c config]" 1>&2
  echo "  -c : config file (default: lustre.yaml)" 1>&2
  exit 1
}

config="lustre.yaml"

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
zone=$(echo "${trimmed_config}" | grep zone | sed -e 's|zone:||g')
if [ "${zone}" = "" ]; then
  echo "The zone is invalid."
  usage
fi

jinja=$(echo "${trimmed_config}" | grep path | sed -e 's|-path:||g')
if [ ! -e "${jinja}" ]; then
  echo "Template file (${jinja}) is not found." 1>&2
  usage
fi

if gcloud deployment-manager deployments describe "${cluster}" >/dev/null 2>&1; then
  gcloud deployment-manager deployments update "${cluster}" --config "${config}" \
    --create-policy "create-or-acquire" --delete-policy "delete"
else
  gcloud deployment-manager deployments create "${cluster}" --config "${config}"
fi

echo "Waiting for the VMs to be ready.."
while :
do
  if gcloud compute ssh "${cluster}-mds1" --zone "${zone}" --tunnel-through-iap \
        --command "sudo journalctl -u google-startup-scripts.service" 2>/dev/null \
        | grep -q -m 1 'Started Google Compute Engine Startup Scripts'; then
    echo "The Lustre cluster got ready."
    break
  else
    sleep 5
  fi
done
