#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo 'install metallb'
kubectl kustomize $DIR/configs/metallb | kubectl apply -f -

echo 'prep helm'
helm repo add openfaas https://openfaas.github.io/faas-netes/
helm repo update

echo 'make storage path'
mkdir /opt/local-path-provisioner

echo 'install Argo CD'
kubectl create namespace argocd
kubectl kustomize $DIR/configs/argocd |kubectl apply -f -
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
# sleep 60
# kubectl get svc -o wide argocd-server -n argocd
# ARGOCD_PW=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
# echo $ARGOCD_PW > /vagrant/argocd-pw

#echo 'get argocd cli'
#curl -L -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v1.2.5/argocd-linux-amd64
#chmod a+x /usr/local/bin/argocd

#echo 'install apps with argocd'
#kubectl apply -f $DIR/apps/local-path-provisioner.yaml
#kubectl apply -f $DIR/apps/nginx-ingress.yaml
#kubectl apply -f $DIR/apps/prometheus-operator.yaml

#argocd login 192.168.50.240 --name admin --password $ARGOCD_PW
#argocd app sync local-path-provisioner
#argocd app sync nginx-ingress
#argocd app sync prometheus-operator

#echo 'installing OpenFaaS'
#kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml

# generate a random password
#PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
#echo $PASSWORD > $DIR/gateway-password.txt

#kubectl -n openfaas create secret generic basic-auth \
#--from-literal=basic-auth-user=admin \
#--from-literal=basic-auth-password="$PASSWORD"

#helm upgrade openfaas --install openfaas/openfaas --namespace openfaas  --set basic_auth=true --set ingress.enabled=true --set faasIdler.dryRun=false

