#!/bin/bash
set -eux

# Inputs for the script
FROM_WIKI_DOMAIN=$1
NEW_PLATFORM_FREE_DOMAIN_SUFFIX=$2

case $NEW_PLATFORM_FREE_DOMAIN_SUFFIX in
  "wbaas.localhost")
    CONTEXT="minikube-wbaas"
    ;;
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

# Hardcoded things
OLD_DOMAIN_SUFFIX="wiki.opencura.com"
TO_WIKI_DOMAIN=${FROM_WIKI_DOMAIN/$OLD_DOMAIN_SUFFIX/$NEW_PLATFORM_FREE_DOMAIN_SUFFIX}

# Nice output of what is happening
echo "Site   : $NEW_PLATFORM_FREE_DOMAIN_SUFFIX"
echo "Cluster: $CONTEXT"
echo "Domain : $FROM_WIKI_DOMAIN => $TO_WIKI_DOMAIN"
echo ""

# Setup var for Wikibase Cloud access
echo "Grabbing k8s pod info"
CLOUD_KUBECTL="kubectl --context=$CONTEXT"

# When copying the file directly, kubectl would error with `error: unexpected EOF` for big files
# A workaround for this seems to be just retrying, conveniently there is a flag for that.
# https://github.com/kubernetes/kubernetes/issues/60140
CLOUD_KUBECTL_COPY="$CLOUD_KUBECTL cp --retries=20"

# Get Some pod names
API_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")
SQL_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/instance=sql,app.kubernetes.io/component=primary -o jsonpath="{.items[0].metadata.name}")
MW_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=mediawiki,app.kubernetes.io/component=app-backend -o jsonpath="{.items[0].metadata.name}")

######################
## Poke data set    ##
######################

# Load old details from wbstack
echo "Tweaking wiki details"
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
WIKI_EMAIL=$(head -n1 ./$FROM_WIKI_DOMAIN/email.txt | xargs echo -n)
######################
## Initial setup    ##
######################

# Call the job to create laravel resources & the mediawiki db (empty)
echo "Running MigrationWikiCreate job"
$CLOUD_KUBECTL_COPY $NEW_WIKI_DETAILS_FILE $API_POD:/tmp/$TO_WIKI_DOMAIN-details.json
$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow MigrationWikiCreate $WIKI_EMAIL /tmp/$TO_WIKI_DOMAIN-details.json"
$CLOUD_KUBECTL exec -it $API_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-details.json"


#######################################
## Sending core data to the new home ##
#######################################

# Migrate images
LOCAL_LOGO_PATH=./$FROM_WIKI_DOMAIN/logo.png
if test -f "$LOCAL_LOGO_PATH"; then
    echo "Importing logo"
    $CLOUD_KUBECTL_COPY $LOCAL_LOGO_PATH $API_POD:/tmp/$TO_WIKI_DOMAIN-logo.png
    $CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow SetWikiLogo domain $TO_WIKI_DOMAIN /tmp/$TO_WIKI_DOMAIN-logo.png"
    $CLOUD_KUBECTL exec -it $API_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-logo.png"
fi

# Migrate the DB data

echo "Fetching fresh data from new wiki entry"
mkdir -p ./$TO_WIKI_DOMAIN
$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:get domain $TO_WIKI_DOMAIN" | tee ./$TO_WIKI_DOMAIN/details.json
WIKI_ID=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.id')
WIKI_DB=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.name')
WIKI_DB_USER=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.user')
WIKI_DB_PASS=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_db.password')
WIKI_QS_NAMESPACE=$(cat ./$TO_WIKI_DOMAIN/details.json | jq -r '.wiki_queryservice_namespace.namespace')

echo $WIKI_DB

echo "Loading wiki DB data"
LOCAL_SQL_PATH=./$FROM_WIKI_DOMAIN/db.sql

# very rough check to validate the completeness of the SQL dump before we upload it
tail $LOCAL_SQL_PATH | grep -q -- '-- Dump completed' 

gzip $LOCAL_SQL_PATH
$CLOUD_KUBECTL_COPY $LOCAL_SQL_PATH.gz $SQL_POD:/tmp/$TO_WIKI_DOMAIN-db.sql.gz
$CLOUD_KUBECTL exec -it $SQL_POD -- sh -c "gunzip /tmp/$TO_WIKI_DOMAIN-db.sql.gz"

$CLOUD_KUBECTL exec -c mariadb -it $SQL_POD -- sh -c "mysql --user=$WIKI_DB_USER --password=$WIKI_DB_PASS $WIKI_DB < /tmp/$TO_WIKI_DOMAIN-db.sql"
$CLOUD_KUBECTL exec -it $SQL_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-db.sql"

########################################
## Running update.php & make writable ##
########################################

# Run update.php to move from 1.35 to 1.37
echo "Running update.php"
$CLOUD_KUBECTL exec -it $MW_POD -- sh -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php ./w/maintenance/update.php --quick"

# Mark the wiki as writable now
# TODO ask when we want to do this...?
echo "Setting to writeable"
$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $TO_WIKI_DOMAIN wgReadOnly"

function run_jobs_in_1000_batches {
    ## Run jobs
    JOBS_TO_GO=1
    # Run in a loop to avoid https://mattermost.wikimedia.de/swe/pl/shgm84oshtbppbm4hu6u6w876r
    while [ "$JOBS_TO_GO" != "0" ]
    do
        echo "Running 1000 jobs"
        $CLOUD_KUBECTL exec -it "$MW_POD" -- bash -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php w/maintenance/runJobs.php --maxjobs 1000"
        echo Waiting for 1 seconds...
        sleep 1
        JOBS_TO_GO=$($CLOUD_KUBECTL exec -it "$MW_POD" -- bash -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php w/maintenance/showJobs.php" | tr -d '[:space:]')
        echo $JOBS_TO_GO jobs to go
    done
}

#######################################
## Elastic search                    ##
#######################################

echo "Not Creating and scheduling population of Elastic search indexes because for now this is disabled"

#######################################
## Query Service                     ##
#######################################

QS_POD=$($CLOUD_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=queryservice -o jsonpath="{.items[0].metadata.name}")

## To clear a namespace from things (if you need it)
## curl 'http://localhost:9999/bigdata/namespace/qsns_b247111900/sparql' -X POST --data-raw 'update=DROP ALL;'

echo "Dumping ttl"
$CLOUD_KUBECTL exec -it "$MW_POD" -- bash -c "mkdir -p /tmp/$TO_WIKI_DOMAIN-ttl"
$CLOUD_KUBECTL exec -it "$MW_POD" -- bash -c "WBS_DOMAIN=$TO_WIKI_DOMAIN php w/extensions/Wikibase/repo/maintenance/dumpRdf.php --output /tmp/$TO_WIKI_DOMAIN-ttl/output.ttl"

## TODO Copy between pods instead of to local disk
LOCAL_TTL_DIR_PATH=./$TO_WIKI_DOMAIN/ttl
LOCAL_TTL_FILE_PATH=./$TO_WIKI_DOMAIN/ttl/output.ttl
echo "Copying TTL from MW to local"
$CLOUD_KUBECTL_COPY "$MW_POD":/tmp/$TO_WIKI_DOMAIN-ttl $LOCAL_TTL_DIR_PATH
echo "Copying TTL from local to query service"
$CLOUD_KUBECTL_COPY $LOCAL_TTL_FILE_PATH "$QS_POD":/tmp/output-$TO_WIKI_DOMAIN.ttl

echo "Removing TTL from MW"
$CLOUD_KUBECTL exec -it "$MW_POD" -- rm -r "/tmp/$TO_WIKI_DOMAIN-ttl"

## in queryservice
echo "Loading ttl into query service"
# Only just a chunk size of 10k so that we don't risk timeouts etc
$CLOUD_KUBECTL exec -it "$QS_POD" -- bash -c "java -cp lib/wikidata-query-tools-*-jar-with-dependencies.jar org.wikidata.query.rdf.tool.Munge --from /tmp/output-$TO_WIKI_DOMAIN.ttl --to /tmp/mungeOut-$TO_WIKI_DOMAIN/wikidump-%09d.ttl.gz --chunkSize 10000 -w $TO_WIKI_DOMAIN --conceptUri https://$TO_WIKI_DOMAIN"
$CLOUD_KUBECTL exec -it "$QS_POD" -- bash -c "./loadData.sh -n $WIKI_QS_NAMESPACE -d /tmp/mungeOut-$TO_WIKI_DOMAIN/"

$CLOUD_KUBECTL exec -it "$QS_POD" -- rm -rf /tmp/mungeOut-$TO_WIKI_DOMAIN/ /tmp/output-$TO_WIKI_DOMAIN.ttl

#######################################
## Final Jobs                        ##
#######################################

# Final run of jobs for good measure
echo "Running jobs again at end of process"
run_jobs_in_1000_batches

echo "Done!"
