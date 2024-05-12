#!/bin/sh
set -e

gum confirm 'Are you ready to start?' || exit 0

rm -f .env azure-creds.json

steampipe plugin uninstall azure

rm ~/.steampipe/config/azure.spc

steampipe plugin uninstall kubernetes

rm ~/.steampipe/config/kubernetes.spc

KUBECONFIG=kubeconfig-01.yaml kubectl --namespace a-team delete \
    --filename crossplane/db-01.yaml

KUBECONFIG=kubeconfig-02.yaml kubectl --namespace a-team delete \
    --filename crossplane/db-02.yaml

az group delete --name $RESOURCE_GROUP --yes

rm kubeconfig*.yaml
