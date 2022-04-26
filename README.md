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

6. Confirm migration appears to have worked
7. Enter the date in the Migration finished column
8. Let the team know
9. Delete your local files containing the data
