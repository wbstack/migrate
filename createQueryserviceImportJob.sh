#!/bin/bash

MW_POD=$(kubectl get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=mediawiki,app.kubernetes.io/component=app-backend -o jsonpath="{.items[0].metadata.name}")
MW_POD_JSON=$(kubectl get pods $MW_POD -o=json)
echo ${MW_POD_JSON} > mw_pod.json

QS_POD=$(kubectl get pods --field-selector='status.phase=Running' -l app.kubernetes.io/name=queryservice -o jsonpath="{.items[0].metadata.name}")
QS_POD_JSON=$(kubectl get pods $QS_POD -o=json)
echo ${QS_POD_JSON} > queryservice_pod.json

kubectl create -f queryServiceImportJob.yaml -o=json --dry-run=client |\
jq -s ".[0].spec.template.spec.initContainers[0].image = .[1].spec.containers[0].image" - mw_pod.json queryservice_pod.json |\
jq ".[0].spec.template.spec.initContainers[0].env = .[1].spec.containers[0].env" |\
jq ".[0].spec.template.spec.containers[0].image = .[2].spec.containers[0].image" |\
jq ".[0].spec.template.spec.containers[0].env = .[2].spec.containers[0].env" |\
jq ".[0]" |\
jq ".spec.template.spec.initContainers[0].env += [{\"name\": \"WBS_DOMAIN\", \"value\": \"${WBS_DOMAIN}\"}]" |\
jq ".spec.template.spec.containers[0].env += [{\"name\": \"WBS_DOMAIN\", \"value\": \"${WBS_DOMAIN}\"}]" |\
jq ".spec.template.spec.containers[0].env += [{\"name\": \"WBS_DOMAIN\", \"value\": \"${WBS_DOMAIN}\"}]" |\
jq ".spec.template.spec.containers[0].env += [{\"name\": \"WIKI_QS_NAMESPACE\", \"value\": \"${WIKI_QS_NAMESPACE}\"}]" |\
kubectl create -f -
