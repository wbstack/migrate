PLATFORM_EMAIL=$(echo $1 | tr -d '[:space:]')

echo Getting data for $PLATFORM_EMAIL

####################################
## Migration process below in sh  ##
####################################
# Setup var for WBStack access
WBSTACK_KUBECTL="kubectl --context=gke_wbstack_us-east1-b_cluster-1"

####################################
## Getting wikis for the user     ##
####################################

# Get Some pod names
echo "Collecting k8s pod infomation"
WBSTACK_SQL_POD=$($WBSTACK_KUBECTL get pods --field-selector='status.phase=Running' -l release=sql,component=master -o jsonpath="{.items[0].metadata.name}")

# And the api user details
DB_API_USER=apiuser
DB_API_PASSWORD=$($WBSTACK_KUBECTL get secrets sql-apiuser --template={{.data.password}} | base64 --decode)

# Get domains for the user, seperated by spaces
USER_DOMAINS=$($WBSTACK_KUBECTL exec -c mariadb -it $WBSTACK_SQL_POD -- sh -c "mysql -u$DB_API_USER -p$DB_API_PASSWORD apidb -N -B -e \"SELECT GROUP_CONCAT( wikis.domain SEPARATOR ' ' ) as domains from wiki_managers, wikis, users WHERE wiki_managers.wiki_id = wikis.id AND wiki_managers.user_id = users.id AND wikis.deleted_at IS NULL AND users.email = '$PLATFORM_EMAIL'\"")
echo "Domains are: $USER_DOMAINS"
echo "---------------------------------------"

for word in $USER_DOMAINS;
do
    TRIMMED_WORD=$(echo $word | tr -d '[:space:]')
    echo "======================================"
    echo "Domain: $TRIMMED_WORD";
    ./getWikiData.sh $TRIMMED_WORD $PLATFORM_EMAIL
    echo "======================================"
done

echo "All Done!"
