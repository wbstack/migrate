#!/bin/bash
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

CLOUD_KUBECTL="kubectl --context=$CONTEXT"
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")
QUERYSERVICE_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=queryservice -o jsonpath="{.items[0].metadata.name}")

QUERYSERVICE_URL=$($CLOUD_KUBECTL exec -it $API_POD -- sh -c 'echo ${QUERY_SERVICE_HOST}')

RWSTORE_PROPERTIES=$($CLOUD_KUBECTL exec -it $API_POD -- cat app/data/RWStore.properties)

$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:get domain $WIKI_DOMAIN" | tee ./$DETAILS_FILE





        # $request->setOptions([
        #     CURLOPT_URL => $url,
        #     CURLOPT_RETURNTRANSFER => true,
        #     CURLOPT_ENCODING => '',
        #     CURLOPT_TIMEOUT => getenv('CURLOPT_TIMEOUT_DELETE_QUERYSERVICE_NAMESPACE') ?: 100,
        #     CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
        #     // User agent is needed by the query service...
        #     CURLOPT_USERAGENT => 'WBStack DeleteQueryserviceNamespaceJob',
        #     CURLOPT_CUSTOMREQUEST => 'DELETE',
        #     CURLOPT_HTTPHEADER => [
        #         'content-type: text/plain',
        #     ],
        # ]);

# Delete Query Service Namespace
echo curl \
    --http1.1 \
    --user-agent 'wikibase.cloud migration recreateQueryServiceNamespace.sh' \
    --request 'DELETE' \
    --header 'content-type: text/plain' \
    --url ${QUERYSERVICE_URL}






        #         $request->setOptions([
        #     // TODO when there are multiple hosts, this will need to be different?
        #     // OR go through the gateway?
        #     CURLOPT_URL => $url,
        #     CURLOPT_RETURNTRANSFER => true,
        #     CURLOPT_ENCODING => '',
        #     CURLOPT_TIMEOUT => 10,
        #     CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
        #     // User agent is needed by the query service...
        #     CURLOPT_USERAGENT => 'WBStack ProvisionQueryserviceNamespaceJob',
        #     CURLOPT_CUSTOMREQUEST => 'POST',
        #     CURLOPT_POSTFIELDS => $properties,
        #     CURLOPT_HTTPHEADER => [
        #         'content-type: text/plain',
        #     ],
        # ]);

# Recreate Query Service Namespace
echo curl \
    --http1.1 \
    --user-agent 'wikibase.cloud migration recreateQueryServiceNamespace.sh' \
    --request 'POST' \
    --header 'content-type: text/plain' \
    --url ${QUERYSERVICE_URL}





