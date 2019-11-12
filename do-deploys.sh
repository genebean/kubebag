#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo 'make storage path'
mkdir -p /opt/local-path-provisioner

# echo 'install metallb'
# kubectl kustomize $DIR/configs/metallb | kubectl apply -f -

echo 'install Argo CD'
kubectl create namespace argocd
kubectl kustomize $DIR/configs/argocd |kubectl apply -f -
# kubectl get svc -o wide argocd-server -n argocd
ARGOCD_PW=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
echo $ARGOCD_PW > /vagrant/argocd-pw

echo 'prep helm'
helm repo update

echo 'install apps with argocd'
helm upgrade applications --install $DIR/apps/ --namespace argocd

#echo 'installing OpenFaaS'
#kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml

# generate a random password
#PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
#echo $PASSWORD > $DIR/gateway-password.txt

#kubectl -n openfaas create secret generic basic-auth \
#--from-literal=basic-auth-user=admin \
#--from-literal=basic-auth-password="$PASSWORD"

#helm upgrade openfaas --install openfaas/openfaas --namespace openfaas  --set basic_auth=true --set ingress.enabled=true --set faasIdler.dryRun=false

