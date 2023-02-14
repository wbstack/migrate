#!/bin/bash
set -eux

WIKI_DOMAIN=$(echo $1 | tr -d '[:space:]')
WIKI_EMAIL=$(echo $2 | tr -d '[:space:]')

echo Getting data for $WIKI_DOMAIN and $WIKI_EMAIL

####################################
## Migration process below in sh  ##
####################################
# Setup var for WBStack access
WBSTACK_KUBECTL="kubectl --context=gke_wbstack_us-east1-b_cluster-1"

####################################
## Getting data from the old home ##
####################################

# Get Some pod names
echo "Collecting k8s pod infomation"
WBSTACK_API_POD=$($WBSTACK_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")
WBSTACK_SQL_POD=$($WBSTACK_KUBECTL get pods --field-selector='status.phase=Running' -l release=sql,component=master -o jsonpath="{.items[0].metadata.name}")
WBSTACK_MW_POD=$($WBSTACK_KUBECTL get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=mediawiki,app.kubernetes.io/component=app-backend -o jsonpath="{.items[0].metadata.name}")

# And the api user details
DB_API_USER=apiuser
DB_API_PASSWORD=$($WBSTACK_KUBECTL get secrets sql-apiuser --template={{.data.password}} | base64 --decode)

# Mark it as no read only, incase we already exported it once...
echo "Resetting to writeable"
$WBSTACK_KUBECTL exec -it $WBSTACK_API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $WIKI_DOMAIN wgReadOnly"

# Get details of the wiki we will be working with (EXTRACTION 1)
echo "Extracting infomation from the API"
mkdir $WIKI_DOMAIN
$WBSTACK_KUBECTL exec -it $WBSTACK_API_POD -- sh -c "php artisan wbs-wiki:get domain $WIKI_DOMAIN" > ./$WIKI_DOMAIN/wbstack.com-details.json
WIKI_ID=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.id')
WIKI_DB=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.wiki_db.name')
WIKI_DB_PREFIX=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.wiki_db.prefix')
WIKI_DB_USER=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.wiki_db.user')
WIKI_DB_PASS=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.wiki_db.password')
WIKI_LOGO=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.settings[] | select(.name == "wgLogo") | .value')
WIKI_FAVICON=$(cat ./$WIKI_DOMAIN/wbstack.com-details.json | jq -r '.settings[] | select(.name == "wgFavicon") | .value')

# And the email owner of the wiki
echo "$WIKI_EMAIL" > ./$WIKI_DOMAIN/email.txt

# Fixing any search SQL issues
#echo "Fixing any search SQL issues"
#$WBSTACK_KUBECTL exec -it "$WBSTACK_MW_POD" -- bash -c "WBS_DOMAIN=$WIKI_DOMAIN php w/maintenance/rebuildtextindex.php"

# Empty the job queue
echo "Emptying the job queue"
$WBSTACK_KUBECTL exec -it "$WBSTACK_MW_POD" -- bash -c "WBS_DOMAIN=$WIKI_DOMAIN php w/maintenance/runJobs.php"

# Set wbstack wiki into READONLY mode
echo "Setting wiki into READONLY mode"
$WBSTACK_KUBECTL exec -it $WBSTACK_API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $WIKI_DOMAIN wgReadOnly 'This wiki will be shutdown in the next weeks. If you want to be migrated to wikibase.cloud please contact Adam!'"

# Grab the logos (EXTRACTION 2)
if [ "$WIKI_LOGO" == "" ];
then
    echo "No logo to grab (skipping)"
else
    echo "Grabbing the logo"
    wget -O ./$WIKI_DOMAIN/logo.png $WIKI_LOGO
fi

# Grab a wiki dump (EXTRACTION 3)
echo "Grabbing the wiki dump"
$WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysqldump -u$WIKI_DB_USER -p$WIKI_DB_PASS $WIKI_DB > /tmp/$WIKI_DB.sql"
$WBSTACK_KUBECTL cp $WBSTACK_SQL_POD:/tmp/$WIKI_DB.sql ./$WIKI_DOMAIN/db.sql
$WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "rm /tmp/$WIKI_DB.sql"

echo "Checking SQL file completness"
if grep -q -- "-- Dump completed on " ./$WIKI_DOMAIN/db.sql
then
    echo "SQL file is complete"
else
    echo "SQL file is not complete"
    echo "You probably want to try again :("
    exit 1
fi

echo "Compressing"
zip -r $WIKI_DOMAIN.zip $WIKI_DOMAIN

echo "And moving to the email directory"
mkdir -p ./.data/$WIKI_EMAIL
mv $WIKI_DOMAIN.zip ./.data/$WIKI_EMAIL/
rm -rf ./$WIKI_DOMAIN

echo "Done!"
