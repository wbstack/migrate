#!/bin/bash
set -e

# Inputs for the script
NEW_PLATFORM_FREE_DOMAIN_SUFFIX="wikibase.dev"
FROM_WIKI_DOMAIN="addshore-alpha.wiki.opencura.com"


# Hardcoded things
OLD_DOMAIN_SUFFIX="wiki.opencura.com"
TO_WIKI_DOMAIN=${FROM_WIKI_DOMAIN/$OLD_DOMAIN_SUFFIX/$NEW_PLATFORM_FREE_DOMAIN_SUFFIX}


# Setup var for Wikibase Cloud access
CLOUD_KUBECTL="kubectl --context=gke_wikibase-cloud_europe-west3-a_wbaas-2"
# Get Some pod names
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")
SQL_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/instance=sql,app.kubernetes.io/component=primary -o jsonpath="{.items[0].metadata.name}")
MW_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=mediawiki,app.kubernetes.io/component=app-backend -o jsonpath="{.items[0].metadata.name}")

######################
## Poke data set    ##
######################

# Load old details from wbstack
WIKI_DETAILS="$(cat ./$FROM_WIKI_DOMAIN/wbstack.com-details.json)"
NEW_WIKI_DETAILS_FILE=./$FROM_WIKI_DOMAIN/$NEW_PLATFORM_FREE_DOMAIN_SUFFIX-details.json
WIKI_DB_PREFIX=$(cat ./$FROM_WIKI_DOMAIN/wbstack.com-details.json | jq -r '.wiki_db.prefix')
# Alter the domain
WIKI_DETAILS=$(echo "$WIKI_DETAILS" | jq ".domain = \"$TO_WIKI_DOMAIN\"")
# Set basic read only setting
WIKI_DETAILS=$(echo "$WIKI_DETAILS" | jq '.settings += [{ "name": "wgReadOnly", "value": "Read only due to ongoing migration" }]')
# Write to a new details file
echo "$WIKI_DETAILS" > $NEW_WIKI_DETAILS_FILE

# Get Email
WIKI_EMAIL=$(cat ./$FROM_WIKI_DOMAIN/email.txt)

######################
## Initial setup    ##
######################

# Call the job to create laravel resources & the mediawiki db (empty)
# $CLOUD_KUBECTL cp $NEW_WIKI_DETAILS_FILE $API_POD:/tmp/$TO_WIKI_DOMAIN-details.json
# $CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow MigrationWikiCreate $WIKI_EMAIL /tmp/$TO_WIKI_DOMAIN-details.json"
# $CLOUD_KUBECTL exec -it $API_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-details.json"

# ##################################
# ## Sending data to the new home ##
# ##################################

# # Migrate images
# TODO merge and deploy https://github.com/wbstack/api/pull/348
#LOCAL_LOGO_PATH=./$FROM_WIKI_DOMAIN/logo.png
#$CLOUD_KUBECTL cp $LOCAL_LOGO_PATH $API_POD:/tmp/$TO_WIKI_DOMAIN-logo.png
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow SetWikiLogo domain $TO_WIKI_DOMAIN /tmp/$TO_WIKI_DOMAIN-logo.png"
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-logo.png"

# Migrate the DB data

mkdir -p ./$TO_WIKI_DOMAIN
$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:get domain $TO_WIKI_DOMAIN" > ./$TO_WIKI_DOMAIN/details.json
WIKI_ID=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.id')
WIKI_DB=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.name')
WIKI_DB_USER=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.user')
WIKI_DB_PASS=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.password')
WIKI_QS_NAMESPACE=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_queryservice_namespace.namespace')

echo $WIKI_DB

LOCAL_SQL_PATH=./$FROM_WIKI_DOMAIN/db.sql
#$CLOUD_KUBECTL cp $LOCAL_SQL_PATH $SQL_POD:/tmp/$TO_WIKI_DOMAIN-db.sql
#$CLOUD_KUBECTL exec -c mariadb -it $SQL_POD -- sh -c "mysql --user=$WIKI_DB_USER --password=$WIKI_DB_PASS $WIKI_DB < /tmp/$TO_WIKI_DOMAIN-db.sql"
#$CLOUD_KUBECTL exec -it $SQL_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-db.sql"


# Run update.php to move from 1.35 to 1.37
# TODO merge and deploy https://github.com/wbstack/mediawiki/pull/212
#$CLOUD_KUBECTL exec -it $MW_POD -- sh -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php ./w/maintenance/update.php --quick"

# Mark the wiki as writable now
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $TO_WIKI_DOMAIN wgReadOnly"


# Fill QueryService
QS_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=queryservice -o jsonpath="{.items[0].metadata.name}")

## To clear a namespace from things
## curl 'http://localhost:9999/bigdata/namespace/qsns_b247111900/sparql' -X POST --data-raw 'update=DROP ALL;'

#$CLOUD_KUBECTL exec -it "$MW_POD" -- bash -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php w/extensions/Wikibase/repo/maintenance/dumpRdf.php --output /tmp/output.ttl"

## TODO Copy between pods instead of to local disk
#$CLOUD_KUBECTL cp "$MW_POD":/tmp/output.ttl /tmp/output.ttl
#$CLOUD_KUBECTL cp /tmp/output.ttl "$QS_POD":/tmp/output.ttl

#$CLOUD_KUBECTL exec -it "$MW_POD" -- rm /tmp/output.ttl

## in queryservice
#$CLOUD_KUBECTL exec -it "$QS_POD" -- bash -c "java -cp lib/wikidata-query-tools-*-jar-with-dependencies.jar org.wikidata.query.rdf.tool.Munge --from /tmp/output.ttl --to /tmp/mungeOut/wikidump-%09d.ttl.gz --chunkSize 100000 -w $TO_WIKI_DOMAIN
#./loadData.sh -n $WIKI_QS_NAMESPACE -d /tmp/mungeOut/"

#$CLOUD_KUBECTL exec -it "$QS_POD" -- rm -rf /tmp/mungeOut/ /tmp/output.ttl


# ##################################### EVERYTHING WORKS ABOVE HERE

# Fill Elastic
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $TO_WIKI_DOMAIN wwExtEnableElasticSearch 1"
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow CirrusSearch\\\\ElasticSearchIndexInit $WIKI_ID"
# TODO deploy mediawiki code update so this next command actually runs
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow CirrusSearch\\\\QueueSearchIndexBatches $WIKI_ID"
# TODO run all jobs


# TODO get the MAX value in the edit_events table on wbstack.com and add ALL of those IDs to the edit_events_table once site is setup
# OR
# TODO run a single updater for each wiki migration with all ids

# TODO, for custom domains we need to setup an ingress & coordniate folks moving the domain over
# TODO adam redirect old domain to new domain (if in control of it
# TODO email the person
