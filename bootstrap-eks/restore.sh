#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved
tar=$(velero backup get | awk '$2 == "Completed" {print $1}' | head -n 1)
[[ $(echo ${tar} | wc -w) -eq 0 ]] && echo "no targets found for restore"
velero restore create bootstrap --from-backup ${tar}
echo "restore bootstrap in progress"
until [[ ! $(velero restore get bootstrap | awk 'NR>1 {print $2}') == "InProgress" ]]; do
  sleep 5
done
velero restore describe bootstrap