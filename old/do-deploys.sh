#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo 'make storage path'
mkdir -p /opt/local-path-provisioner

echo 'prep helm'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo 'install Argo CD'
helm dependency update $DIR/configs/argocd
helm upgrade argocd --install $DIR/configs/argocd/ --namespace argocd
ARGOCD_PW=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
echo $ARGOCD_PW > /vagrant/argocd-pw

echo 'install apps with argocd'
helm upgrade applications --install $DIR/apps/ --namespace argocd
