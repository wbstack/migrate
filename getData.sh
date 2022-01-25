WIKI_DOMAIN="addshore-alpha.wiki.opencura.com"


####################################
## Migration process below in sh  ##
####################################
# Setup var for WBStack access
WBSTACK_KUBECTL="kubectl --context=gke_wbstack_us-east1-b_cluster-1"

####################################
## Getting data from the old home ##
####################################

# Get Some pod names
WBSTACK_API_POD=$($WBSTACK_KUBECTL get pods -l app.kubernetes.io/name=api,app.kubernetes.io/component=queue -o jsonpath="{.items[0].metadata.name}")
WBSTACK_SQL_POD=$($WBSTACK_KUBECTL get pods -l release=sql,component=master -o jsonpath="{.items[0].metadata.name}")

# And the api user details
DB_API_USER=apiuser
DB_API_PASSWORD=$($WBSTACK_KUBECTL get secrets sql-apiuser --template={{.data.password}} | base64 --decode)

# Get details of the wiki we will be working with (EXTRACTION 1)
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
WIKI_EMAIL=$($WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysql -u$DB_API_USER -p$DB_API_PASSWORD apidb -N -B -e \"SELECT email FROM wiki_managers, users WHERE wiki_managers.wiki_id = $WIKI_ID AND wiki_managers.user_id = users.id\"")
echo "$WIKI_EMAIL" > ./$WIKI_DOMAIN/email.txt

# Set wbstack wiki into READONLY mode
# $WBSTACK_KUBECTL exec -it $WBSTACK_API_POD -- sh -c "php artisan wbs-wiki:setSetting domain $WIKI_DOMAIN wgReadOnly 'This wiki is currently being migrated to wikibase.cloud'"

# Grab the logos (EXTRACTION 2)
wget -O ./$WIKI_DOMAIN/favicon.ico $WIKI_FAVICON
wget -O ./$WIKI_DOMAIN/logo.png $WIKI_LOGO

# Grab a wiki dump (EXTRACTION 3)
$WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysqldump -u$WIKI_DB_USER -p$WIKI_DB_PASS $WIKI_DB > /tmp/$WIKI_DB.sql"
$WBSTACK_KUBECTL cp $WBSTACK_SQL_POD:/tmp/$WIKI_DB.sql ./$WIKI_DOMAIN/db.sql
$WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "rm /tmp/$WIKI_DB.sql"

# Grab the latest wikibase entitiy ID counters from the wiki (EXTRACTION 4)
$WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysql -u$WIKI_DB_USER -p$WIKI_DB_PASS $WIKI_DB -N -B -e \"SELECT JSON_OBJECT('id_value',id_value,'id_type',id_type) FROM ${WIKI_DB_PREFIX}_wb_id_counters\"" > ./$WIKI_DOMAIN/ids.jsonl
# And extract the max wikibase entity IDs we will need to enter...
MAX_ITEM=$(cat ./$WIKI_DOMAIN/ids.jsonl | jq '. | select(.id_type | contains("wikibase-item")) | .id_value')
MAX_PROPERTY=$(cat ./$WIKI_DOMAIN/ids.jsonl | jq '. | select(.id_type | contains("wikibase-property")) | .id_value')
MAX_LEXEME=$(cat ./$WIKI_DOMAIN/ids.jsonl | jq '. | select(.id_type | contains("wikibase-lexeme")) | .id_value')