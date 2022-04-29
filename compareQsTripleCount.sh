#!/bin/bash

# You can use this script as a quick way to compare the triple count in the query service of an old and new wiki.
# example usage: ./compareQsTripleCount.sh biodiversity.wiki.opencura.com biodiversity.wikibase.cloud

OLD_WIKI=$1
NEW_WIKI=$2

function count_triples {
    WIKI_DOMAIN=$1
    QUERY="SELECT%20(COUNT(*)%20AS%20%3Fc)%20%7B%20%3Fs%20%3Fp%20%3Fo.%20%7D%0A%0A"
    RESPONSE=$(curl -s "https://$WIKI_DOMAIN/query/sparql?query=$QUERY" -H 'Accept: application/sparql-results+json')

    COUNT_TRIPLES=$(echo $RESPONSE | jq -r .results.bindings[0].c.value)

    echo $COUNT_TRIPLES
}

OLD_WIKI_TRIPLE_COUNT=$(count_triples $OLD_WIKI)
NEW_WIKI_TRIPLE_COUNT=$(count_triples $NEW_WIKI)

echo -e "$OLD_WIKI\t$(count_triples $OLD_WIKI)"
echo -e "$NEW_WIKI\t$(count_triples $NEW_WIKI)"
echo

if [[ "$NEW_WIKI_TRIPLE_COUNT" -gt "$OLD_WIKI_TRIPLE_COUNT" ]]; then
    echo "good news: new wiki triple count is greater than the old one - this is expected"
else
    echo "new wiki triple count is *NOT* greater than the old one - time to investigate"
fi
