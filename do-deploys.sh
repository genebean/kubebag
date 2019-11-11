#!/usr/bin/env bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo 'install metallb'
kubectl kustomize $DIR/configs/metallb | kubectl apply -f -

echo 'prep helm'
helm repo add openfaas https://openfaas.github.io/faas-netes/
helm repo update

echo 'install nginx ingress controller'
helm install stable/nginx-ingress --values $DIR/configs/nginx-ingress/values.yaml --name nginx-ingress --namespace nginx-ingress
sleep 5
kubectl --namespace nginx-ingress get services -o wide nginx-ingress-controller

#echo 'installing Prometheus'
#kubectl create namespace monitoring
#helm upgrade prometheus-operator --install stable/prometheus-operator --namespace monitoring --set prometheus.ingress.enabled=true --set alertmanager.ingress.enabled=true --set grafana.ingress.enabled=true

echo 'installing OpenFaaS'
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml

# generate a random password
PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
echo $PASSWORD > $DIR/gateway-password.txt

kubectl -n openfaas create secret generic basic-auth \
--from-literal=basic-auth-user=admin \
--from-literal=basic-auth-password="$PASSWORD"

helm upgrade openfaas --install openfaas/openfaas --namespace openfaas  --set basic_auth=true --set ingress.enabled=true --set faasIdler.dryRun=false

