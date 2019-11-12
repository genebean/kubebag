#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo 'make storage path'
mkdir -p /opt/local-path-provisioner

echo 'install Argo CD'
kubectl create namespace argocd
kubectl kustomize $DIR/configs/argocd |kubectl apply -f -
ARGOCD_PW=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
echo $ARGOCD_PW > /vagrant/argocd-pw

echo 'prep helm'
helm repo update

echo 'install apps with argocd'
helm upgrade applications --install $DIR/apps/ --namespace argocd

