#!/bin/bash
set -ex

# Inputs for the script
EMAIL=$1
TARGET=$2

if [[ -z "$EMAIL" ]]; then
    echo "You must supply an email address as the first argument"
    exit 1
fi

case $TARGET in
  "wikibase.dev")
    CONTEXT="gke_wikibase-cloud_europe-west3-a_wbaas-2"
    ;;
  "wikibase.cloud")
    CONTEXT="gke_wikibase-cloud_europe-west3-a_wbaas-3"
    ;;
  *)
    echo "You must supply wikibase.dev or wikibase.cloud as the second argument"
    exit 2
    ;;
esac

CLOUD_KUBECTL="kubectl --context=$CONTEXT"
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")

$CLOUD_KUBECTL exec $API_POD -i -- php artisan tinker <<EOF
User::create(
    [
        'email' => '$EMAIL',
        'verified' => 1,
        'password' => 'nothing-hashes-to-me'
    ]
);
EOF
