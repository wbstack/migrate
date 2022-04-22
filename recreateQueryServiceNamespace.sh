#!/bin/bash

# https://phabricator.wikimedia.org/T306693

set -eux

WIKI_DOMAIN=$1
NEW_PLATFORM_FREE_DOMAIN_SUFFIX=$2

case $NEW_PLATFORM_FREE_DOMAIN_SUFFIX in
  "wikibase.dev")
    CONTEXT="gke_wikibase-cloud_europe-west3-a_wbaas-2"
    ;;
  "wikibase.cloud")
    CONTEXT="gke_wikibase-cloud_europe-west3-a_wbaas-3"
    ;;
  *)
    echo "You must supply wikibase.dev or wikibase.cloud as the second argument"
    exit 1
    ;;
esac

DETAILS_FILE=recreateQS-$WIKI_DOMAIN-details.json
RWSTORE_PROPERTIES_FILE=recreateQS-$WIKI_DOMAIN-post.data
REMOTE_RWSTORE_PROPERTIES_FILE=/tmp/$RWSTORE_PROPERTIES_FILE

CLOUD_KUBECTL="kubectl --context=$CONTEXT"
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")

$CLOUD_KUBECTL exec $API_POD -- sh -c "php artisan wbs-wiki:get domain $WIKI_DOMAIN" > ./$DETAILS_FILE
$CLOUD_KUBECTL exec $API_POD -- sh -c "cat app/data/RWStore.properties" > ./$RWSTORE_PROPERTIES_FILE

WIKI_DETAILS="$(cat ./$DETAILS_FILE)"
WIKI_QS_BACKEND=$(echo $WIKI_DETAILS | jq -r '.wiki_queryservice_namespace.backend')
WIKI_QS_NAMESPACE=$(echo $WIKI_DETAILS | jq -r '.wiki_queryservice_namespace.namespace')

sed -i "s/REPLACE_NAMESPACE/${WIKI_QS_NAMESPACE}/" ./$RWSTORE_PROPERTIES_FILE

# Delete Query Service Namespace
# https://github.com/wbstack/api/blob/main/app/Jobs/DeleteQueryserviceNamespaceJob.php#L59
CURL_DELETE_QS="curl -s --http1.1 --user-agent 'wikibase.cloud migration recreateQueryServiceNamespace.sh' --request 'DELETE' --header 'content-type: text/plain' --url '${WIKI_QS_BACKEND}/bigdata/namespace/${WIKI_QS_NAMESPACE}'"

$CLOUD_KUBECTL exec $API_POD -- sh -c "$CURL_DELETE_QS"

# Recreate Query Service Namespace
# https://github.com/wbstack/api/blob/main/app/Jobs/ProvisionQueryserviceNamespaceJob.php#L65
CURL_CREATE_QS="curl -s --http1.1 --user-agent 'wikibase.cloud migration recreateQueryServiceNamespace.sh' --request 'POST' --header 'content-type: text/plain' --data @$REMOTE_RWSTORE_PROPERTIES_FILE --url '${WIKI_QS_BACKEND}/bigdata/namespace'"

$CLOUD_KUBECTL cp ./$RWSTORE_PROPERTIES_FILE $API_POD:$REMOTE_RWSTORE_PROPERTIES_FILE
$CLOUD_KUBECTL exec $API_POD -- sh -c "$CURL_CREATE_QS"
$CLOUD_KUBECTL exec $API_POD -- sh -c "rm $REMOTE_RWSTORE_PROPERTIES_FILE"