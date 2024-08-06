# Kubebag

Kubebag is my playground where I am learning about k8s by trying to create a Kubernetes-based setup that I really like and that could replace other things.

## Setup

Install virt-manager and deps. Edit "default" network via `virsh net-edit default` and make the dhcp pool start at 100.

If not already installed.....

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Next, get Fedora CoreOS running:

```bash
virt-install --name=fcos --vcpus=3 --ram=6144 \
--os-variant=fedora-coreos-stable \
--import \
--network=bridge=virbr0 \
--disk=size=20,backing_store=/home/gene/Downloads/fedora-coreos.qcow2 \
--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=/home/gene/repos/kubebag/server.ign" \
--graphics=none
```

Copy over a kube connfig and bootstrap things:

```bash
# Update to IP of CoreOS. This should match what is in server.bu
IPADDRESS=192.168.122.10
echo 'Waiting for K3s to generate a kubeconfig for us and then downloading it...'
ssh -o UserKnownHostsFile=/dev/null $IPADDRESS "until [ -f "/etc/rancher/k3s/k3s.yaml" ]; do \
sleep 5; done; cat /etc/rancher/k3s/k3s.yaml" \
|sed 's/default/k3s/g' |sed "s/127\.0\.0\.1/$IPADDRESS/" > ~/.kube/config
chmod 600 ~/.kube/config
echo
echo 'Listing namespaces to verify kubectl is working...'
kubectl get ns
echo
echo 'updating local charts quietly'
for d in $(ls charts/); do helm dependency update charts/$d; done >/dev/null
echo 'updating charts used during bootstrapping...'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add cilium https://helm.cilium.io/
echo
helm repo update
echo
echo 'Installing Cilium'
echo
helm upgrade --install cilium cilium/cilium --version 1.16.0 \
  --namespace kube-system \
  --set bpf.datapathMode=netkit \
  --set cni.exclusive=false \
  --set envoy.enabled=false \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16" \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443 \
  --set kubeProxyReplacement=true \
  --set operator.replicas=1

cilium status --wait

sleep 5

kubectl get pods --all-namespaces \
-o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork \
--no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod

sleep 30

helm upgrade --install --namespace argocd --create-namespace \
argocd argo/argo-cd --set configs.params."server.insecure"=true

helm template ./apps-of-apps/infra-stage-1 |kubectl apply -f -

echo 'Starting to check for everything being ready'
until [ $(kubectl -n argocd get Applications |tr -s ' ' | cut -d ' ' -f3 | grep -c Healthy) -gt 0 ]; do echo 'Waiting for health status to be reported'; kubectl -n argocd get Applications; echo; sleep 5; done
until [ $(kubectl -n argocd get Applications |tr -s ' ' | cut -d ' ' -f2 | grep -c Unknown) -gt 0 ]; do  echo 'Waiting for sync status to be reported'; kubectl -n argocd get Applications; echo; sleep 5; done
until [ $(kubectl -n argocd get Applications |tr -s ' ' | cut -d ' ' -f2 | grep -v Synced -c) -eq 1 ]; do  echo 'Waiting for all apps to be synced'; kubectl -n argocd get Applications; echo; sleep 5; done
until [ $(kubectl -n argocd get Applications |tr -s ' ' | cut -d ' ' -f3 | grep -v Healthy -c) -eq 1 ]; do  echo 'Waiting for all apps to be healthy'; kubectl -n argocd get Applications; echo; sleep 5; done
```

Generate trust anchor for Linkerd:

```bash
step certificate create root.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure  --not-after=87600h
```

Create, save, and apply sealed secret for trust anchor

```bash
kubectl -n linkerd create secret tls \
  linkerd-trust-anchor \
  --cert=ca.crt \
  --key=ca.key \
  --dry-run=client -o yaml | \
kubeseal --controller-name=sealed-secrets \
--controller-namespace=kubeseal -o yaml > charts/linkerd-control-plane/templates/sealed-linkerd-trust-anchor.yaml
```

Update ca cert in `charts/linkerd-control-plane/values.yaml` with one generated above and then commit to git and push.

Get Gandi PAT:

```bash
read -s EXTERNAL_DNS_GANDI
```

Create the secret for Gandi:

```bash
export EXTERNAL_DNS_GANDI $EXTERNAL_DNS_GANDI
kubectl -n external-dns create secret generic \
  sealed-gandi \
  --from-literal=GANDI_PAT=$EXTERNAL_DNS_GANDIa \
  --dry-run=client -o yaml | \
kubeseal --controller-name=sealed-secrets \
--controller-namespace=kubeseal -o yaml > charts/traefik-v3/templates/gateway-class-traefik-v3.yaml
```

```bash
helm template ./apps-of-apps/infra-stage-2 |kubectl apply -f -
```

At this stage stuff works. Set a new admin password and then go look at the web interface:

In another terminal

```bash
kubectl port-forward service/argocd-server -n argocd 8080:443
```

In original terminal

```bash
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

~/argocd login localhost:8080 --insecure --username admin --password $ARGOCD_PW
~/argocd account update-password --current-password $ARGOCD_PW
~/argocd login localhost:8080 --insecure --username admin # use new password

```

## To Do / Notes

- checked out viz dashboard via laptop
- will need to enforce the that the following annotation is on everything but cert-manager
  `linkerd.io/inject: enabled`
