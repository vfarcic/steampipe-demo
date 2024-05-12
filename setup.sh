#!/bin/sh
set -e

echo "# Setup

This setup uses Azure to create cluster. Please open an issue if you would like a different provider to be added to the script.

" | gum format

gum confirm 'Are you ready to start?' || exit 0

############
# Clusters #
############

echo "## Clusters" | gum format

az login

export RESOURCE_GROUP=dot-$(date +%Y%m%d%H%M%S)
echo "export RESOURCE_GROUP=$RESOURCE_GROUP" >> .env

export LOCATION=eastus
echo "export LOCATION=$LOCATION" >> .env

az group create --name $RESOURCE_GROUP --location $LOCATION

export KUBECONFIG=$PWD/kubeconfig-00.yaml
echo "export KUBECONFIG=$KUBECONFIG" >> .env

for INDEX in 00 01 02 03; do

    az aks create --resource-group $RESOURCE_GROUP \
        --name dot-$INDEX --node-count 1 \
        --node-vm-size Standard_B2s --yes

    az aks get-credentials --resource-group $RESOURCE_GROUP \
        --name dot-$INDEX --file kubeconfig-$INDEX.yaml

done

export SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az ad sp create-for-rbac --sdk-auth --role Owner \
    --scopes /subscriptions/$SUBSCRIPTION_ID \
    | tee azure-creds.json

########
# Apps #
########

echo "## Apps" | gum format

for INDEX in 01 02 03; do

    KUBECONFIG=kubeconfig-$INDEX.yaml timoni --namespace a-team \
        apply silly-demo \
        oci://ghcr.io/vfarcic/silly-demo-package \
        --version 1.4.123

done

KUBECONFIG=kubeconfig-02.yaml timoni --namespace a-team apply \
    something-else oci://ghcr.io/vfarcic/silly-demo-package \
    --version 1.4.123

KUBECONFIG=kubeconfig-02.yaml timoni --namespace a-team apply \
    how-about-this oci://ghcr.io/vfarcic/silly-demo-package \
    --version 1.4.123 --values values-how-about-this.yaml \
    --wait=false

##############
# Crossplane #
##############

echo "## Crossplane" | gum format

set +e
helm repo add crossplane-stable https://charts.crossplane.io/stable
set -e

helm repo update

for INDEX in 01 02; do

    KUBECONFIG=kubeconfig-$INDEX.yaml helm upgrade --install \
        crossplane crossplane-stable/crossplane \
        --namespace crossplane-system --create-namespace --wait

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl apply \
        --filename crossplane/provider-kubernetes-incluster.yaml

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl apply \
        --filename crossplane/config-sql.yaml

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl \
        --namespace crossplane-system \
        create secret generic azure-creds \
        --from-file creds=./azure-creds.json

done

echo "## Waiting for Crossplane packages..." | gum format

for INDEX in 01 02; do

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl wait \
        --for=condition=healthy provider.pkg.crossplane.io \
        --all --timeout=600s

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl apply \
        --filename crossplane/provider-config-azure.yaml

    KUBECONFIG=kubeconfig-$INDEX.yaml kubectl --namespace a-team \
        apply --filename crossplane/db-$INDEX.yaml

done
