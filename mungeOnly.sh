#!/bin/bash
set -eux

exit 1 # WIP

# Inputs for the script
FROM_WIKI_DOMAIN=$1
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

CLOUD_KUBECTL="kubectl --context=$CONTEXT"
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")

$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:get domain $TO_WIKI_DOMAIN" > ./$TO_WIKI_DOMAIN/details.json
WIKI_QS_NAMESPACE=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_queryservice_namespace.namespace')

#######################################
## Query Service                     ##
#######################################

QS_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=queryservice -o jsonpath="{.items[0].metadata.name}")

## TODO Copy between pods instead of to local disk
# When copying the file directly, kubectl would error with `error: unexpected EOF` for big files
# Stackoverflow and github suggested trying to copy a directory instead, and that seems to work...
# https://github.com/kubernetes/kubernetes/issues/60140#issuecomment-836448850
LOCAL_TTL_DIR_PATH=./$TO_WIKI_DOMAIN/ttl
LOCAL_TTL_FILE_PATH=./$TO_WIKI_DOMAIN/ttl/output.ttl

echo "Copying TTL from local to query service"
$CLOUD_KUBECTL cp $LOCAL_TTL_FILE_PATH "$QS_POD":/tmp/output-$TO_WIKI_DOMAIN.ttl

## in queryservice
echo "Loading ttl into query service"
# Only just a chunk size of 10k so that we don't risk timeouts etc
$CLOUD_KUBECTL exec -it "$QS_POD" -- bash -c "java -cp lib/wikidata-query-tools-*-jar-with-dependencies.jar org.wikidata.query.rdf.tool.Munge --from /tmp/output-$TO_WIKI_DOMAIN.ttl --to /tmp/mungeOut-$TO_WIKI_DOMAIN/wikidump-%09d.ttl.gz --chunkSize 10000 -w $TO_WIKI_DOMAIN"
$CLOUD_KUBECTL exec -it "$QS_POD" -- bash -c "./loadData.sh -n $WIKI_QS_NAMESPACE -d /tmp/mungeOut-$TO_WIKI_DOMAIN/"

$CLOUD_KUBECTL exec -it "$QS_POD" -- rm -rf /tmp/mungeOut-$TO_WIKI_DOMAIN/ /tmp/output-$TO_WIKI_DOMAIN.ttl

