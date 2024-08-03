# Kubebag

Kubebag is my playground where I am learning about k8s by trying to create a Kubernetes-based setup that I really like and that could replace other things.

## Setup

Get Fedora CoreOS running:

```bash
virt-install --name=fcos --vcpus=3 --ram=6144 \
--os-variant=fedora-coreos-stable \
--import \
--network=bridge=virbr0 \
--disk=size=20,backing_store=/home/gene/Downloads/fedora-coreos.qcow2 \
--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=/home/gene/Downloads/server.ign" \
--graphics=none
```

Copy over a kube connfig:

```bash
IPADDRESS=192.168.122.118 # update to IP of CoreOS
ssh -o UserKnownHostsFile=/dev/null $IPADDRESS cat /etc/rancher/k3s/k3s.yaml |sed 's/default/k3s/g' |sed "s/127\.0\.0\.1/$IPADDRESS/" > ~/.kube/config
```

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

Bootstrap stuff:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add cilium https://helm.cilium.io/

helm repo update

helm upgrade --install cilium cilium/cilium --version 1.16.0 \
  --namespace kube-system \
  --set bpf.datapathMode=netkit \
  --set cni.exclusive=false \
  --set envoy.enabled=false \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16" \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443 \
  --set kubeProxyReplacement=true \
  --set operator.replicas=1 \
  --set securityContext.privileged=true

cilium status --wait

sleep 5

kubectl get pods --all-namespaces \
-o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork \
--no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod

sleep 30

helm upgrade --install --namespace argocd --create-namespace \
argocd argo/argo-cd --set configs.params."server.insecure"=true

helm template ./infra-stage-1 |kubectl apply -f -
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
--controller-namespace=kubeseal -o yaml > infra-stage-2/templates/linkerd/sealed-linkerd-trust-anchor.yaml
```

Update ca cert in linkerd-control-plane with one generated above and then commit to git and push.

```bash
helm template ./infra-stage-2 |kubectl apply -f -
```

At this stage stuff works. Go look at the web interface:

In another terminal

```bash
kubectl port-forward service/argocd-server -n argocd 8080:443
```

In original terminal

```bash
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

~/argocd login localhost:8080 --insecure --username admin --password $ARGOCD_PW
~/argocd account update-password --current-password $ARGOCD_PW
```

## To Do / Notes

- checked out viz dashboard via laptop
- will need to enforce the that the following annotation is on everything but cert-manager
  `linkerd.io/inject: enabled`
- Will need to setup LB IPAM like what is talked about in https://blog.stonegarden.dev/articles/2024/02/bootstrapping-k3s-with-cilium/#enable-ssh-server-optional
