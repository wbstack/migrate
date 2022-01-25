#!/bin/bash
set -e

# Inputs for the script
NEW_DOMAIN_SUFFIX="wikibase.dev"
FROM_WIKI_DOMAIN="addshore-alpha.wiki.opencura.com"


# Hardcoded things
OLD_DOMAIN_SUFFIX="wiki.opencura.com"
TO_WIKI_DOMAIN=${FROM_WIKI_DOMAIN/$OLD_DOMAIN_SUFFIX/$NEW_DOMAIN_SUFFIX}

# Break for now on NON default wiki domain suffix
if [[ "$FROM_WIKI_DOMAIN" == "$TO_WIKI_DOMAIN" ]]; then
  echo "This script is only ready to migrate default domains currently (something went wrong with domain altering)"
  exit 1
fi

# Setup var for Wikibase Cloud access
CLOUD_KUBECTL="kubectl --context=gke_wikibase-cloud_europe-west3-a_wbaas-2"
# Get Some pod names
API_POD=$($CLOUD_KUBECTL get pods -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")

######################
## Poke data set    ##
######################

# Load old details from wbstack
WIKI_DETAILS="$(cat ./$FROM_WIKI_DOMAIN/wbstack.com-details.json)"
NEW_WIKI_DETAILS_FILE=./$FROM_WIKI_DOMAIN/$NEW_DOMAIN_SUFFIX-details.json
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
#LOCAL_LOGO_PATH=./$FROM_WIKI_DOMAIN/logo.png
#$CLOUD_KUBECTL cp $LOCAL_LOGO_PATH $API_POD:/tmp/$TO_WIKI_DOMAIN-logo.png
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "php artisan job:dispatchNow SetWikiLogo domain $TO_WIKI_DOMAIN /tmp/$TO_WIKI_DOMAIN-logo.png"
#$CLOUD_KUBECTL exec -it $API_POD -- sh -c "rm /tmp/$TO_WIKI_DOMAIN-logo.png"

# TODO everything works above here!

# Migrate the DB data


# TODO oposite of this?
#$CLOUD_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysqldump -u$WIKI_DB_USER -p$WIKI_DB_PASS $WIKI_DB > /tmp/$WIKI_DB.sql"
#$CLOUD_KUBECTL cp $WBSTACK_SQL_POD:/tmp/$WIKI_DB.sql ./$WIKI_DOMAIN/db.sql
#$CLOUD_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "rm /tmp/$WIKI_DB.sql"

# TODO get the NEW wiki db name, user, password
# TODO copy the SQL dump to the sql server
# TODO load the dump to a new DB (mysql -u username -p database_name < file.sql)

# Update.php
# TODO run update.php for the site (XXX: can this happen in readonly mode?)

# TODO could just un read only here

# Fill QueryService
# TODO get the MAX value in the edit_events table on wbstack.com and add ALL of those IDs to the edit_events_table once site is setup

# Fill Elastic
# TODO trigger creating of elastic indexes (Before this point)
# TODO trigger force search index population

# TODO empty the job queue

# TODO no longer readonly

# TODO, for custom domains we need to setup an ingress & coordniate folks moving the domain over
# TODO adam redirect old domain to new domain (if in control of it
# TODO email the person