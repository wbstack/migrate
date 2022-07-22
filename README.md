# migrate

Repository containing code enabling migration from wbstack.com to wikibase.cloud

## Simple steps to follow
1. Look in migration sheet for a user to migrate
2. Enter the date in the migration started column
3. Download all their private wiki zips from the shared drive
4. Unzip them in the same folder as there is a copy of putData.sh
5. Execute putData.sh

```
$ ./putData.sh potato.wiki.opencura.com wikibase.cloud
```

6. Remove the triple dump date from the queryservice using the following script
 [queryservice-delete-dump-timestamp-in-namespace](https://github.com/wmde/wbaas-deploy/blob/main/bin/queryservice-delete-dump-timestamp-in-namespaces) from the wbaas-deploy repo.
This is so that the queryservice updater does not use the triple dump date created during migration.
   1. Create a file containing the wiki namespace, say `namespace.txt`.
      In the api backend application run `Wiki::where(['domain' => '<my-domain-here>'])->first()->wikiQueryserviceNamespace;` to get the wiki namespace.
   2. Forward the query service port to the host machine
      `kubectl port-forward deployment/queryservice 9999:9999`.
   3. Run the `queryservice-delete-dump-timestamp-in-namespace` script and pass `namespace.txt` as an argument.
7. Confirm migration appears to have worked by opening the following links on your browser.
    1. Check that the migrated wiki [potato.wikibase.cloud](potato.wikibase.cloud) works. 
    2. Check that Query Service works.
    3. Check that Cradle works.
    4. Check that QuickStatement works.
8. Enter the date in the Migration finished column
9. Let the team know
10. Delete your local files containing the data
