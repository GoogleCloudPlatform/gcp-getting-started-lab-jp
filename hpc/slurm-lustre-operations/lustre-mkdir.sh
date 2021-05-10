#!/bin/sh
set -eu

cmdname=$( basename "$0" )

usage() {
  echo "Usage: ${cmdname} [-c config] [-d directory]" 1>&2
  echo "  -c : config file (default: lustre.yaml)" 1>&2
  echo "  -d : directory" 1>&2
  exit 1
}

config="lustre.yaml"
directory=""

while getopts c:d:h opt
do
  case $opt in
    "c" ) config="${OPTARG}" ;;
    "d" ) directory="${OPTARG}" ;;
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

if [ "${directory}" = "" ]; then
  gcloud compute ssh "${cluster}-mds1" --zone "${zone}" \
    --command "sudo sh -c 'mkdir -p work && mount -t lustre ${cluster}-mds1:/lustre work && ls -la work && umount work && rm -rf work'"
else
  gcloud compute ssh "${cluster}-mds1" --zone "${zone}" \
    --command "sudo sh -c 'mkdir -p work && mount -t lustre ${cluster}-mds1:/lustre work && cd work && mkdir -p ${directory} && lfs setstripe -c -1 ${directory} && cd .. && ls -la work && umount work && rm -rf work'"
fi
