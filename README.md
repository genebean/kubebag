# Kubebag

Kubebag is my playground where I am learning about k8s by trying to create a Kubernetes-based setup that I really like and that could replace other things.

## Prep

### virt-manager

Install virt-manager and deps. 

### CLI Tools

#### Cilium cli

`nix shell nixpkgs#cilium-cli` or `brew install cilium-cli`

OR

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

#### Hubble cli

`nix shell nixpkgs#hubble` or `brew install hubble`

OR

```bash
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
rm hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
```

#### Argo CD cli

`brew install argocd`

OR

```bash
VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

### Get Fedora CoreOS running

#### Download an image

```bash
mkdir -p $HOME/.local/share/libvirt/images
podman run --rm -v $HOME/.local/share/libvirt/images/:/data -w /data \
quay.io/coreos/coreos-installer:release download -s stable -p qemu -f qcow2.xz --decompress
mv $HOME/.local/share/libvirt/images/fedora-coreos-* $HOME/.local/share/libvirt/images/fedora-coreos.qcow2
```

If you have an older image downloaded the above may throw an error... just clean up the older image and do the move again.

#### Update Ignition file, if needed

```bash
podman run -i --rm quay.io/coreos/butane:release \
--pretty --strict < server.bu > server.ign
```

#### Destroy previous vm

```bash
virsh destroy fcos && virsh undefine --remove-all-storage fcos
```

#### Start vm

This setup assumes you have two bridges:

- `br0`: bridges to the LAN
- `virbr0`: the default bridge that is NAT'ed

Edit "default" network and make the DHCP pool start at 100

```bash
sudo virsh net-edit default
sudo virsh net-autostart default
sudo virsh net-destroy --network default
sudo virsh net-start --network default
```

Create a file name `br0.xml` containing this:

```xml
<network>
  <name>br0</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
```

Create the `br0` interface in libvirt:

```bash
virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0
```

Make it possible for other things to talk to the VM:

>this was taken from https://gist.github.com/plembo/a7b69f92953a76ab2d06533754b5e2bb
 
```bash
sudo modprobe br_netfilter
```

Start up the VM:

```bash
virt-install --name=fcos --vcpus=3 --ram=6144 \
--os-variant=fedora-coreos-stable \
--import \
--network=bridge=br0 \
--network=bridge=virbr0 \
--disk=size=20,backing_store=$HOME/.local/share/libvirt/images/fedora-coreos.qcow2 \
--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=/home/gene/repos/kubebag/server.ign" \
--graphics=none
```

**NOTE:** to get out of the serial console, press `Ctrl + ]`

## Copy over a kube connfig and bootstrap things

```bash
# Update to IP of CoreOS. This should match what is in server.bu
IPADDRESS=192.168.20.170
mkdir -p $HOME/.kube
echo 'Waiting for K3s to generate a kubeconfig for us and then downloading it...'
ssh -o UserKnownHostsFile=/dev/null gene@$IPADDRESS "until [ -f "/etc/rancher/k3s/k3s.yaml" ]; do \
sleep 5; done; cat /etc/rancher/k3s/k3s.yaml" \
|sed 's/default/k3s/g' |sed "s/127\.0\.0\.1/$IPADDRESS/" > ~/.kube/k3s-libvirt-config
chmod 600 ~/.kube/k3s-libvirt-config
export KUBECONFIG="$HOME/.kube/k3s-libvirt-config"
echo
echo 'Listing namespaces to verify kubectl is working...'
until kubectl get ns; do sleep 5; done
echo
echo 'updating charts used during bootstrapping...'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add cilium https://helm.cilium.io/
echo
helm repo update
echo 'updating local charts quietly'
for d in $(ls charts/); do helm dependency update charts/$d; done >/dev/null
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

until cilium status --wait; do echo 'cilium status timed out, trying again'; sleep 2; done

sleep 5

kubectl get pods --all-namespaces \
-o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork \
--no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod

sleep 30

helm upgrade --install argocd argo/argo-cd \
--create-namespace --namespace argocd \
--set configs.params.'server.insecure'=true \
--set configs.cm.'application.resourceTrackingMethod'=annotation

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
  --from-literal=GANDI_PAT=$EXTERNAL_DNS_GANDI \
  --dry-run=client -o yaml | \
kubeseal --controller-name=sealed-secrets \
--controller-namespace=kubeseal -o yaml > charts/external-dns/templates/sealed-gandi.yaml
```

Commit and push gandi sealed secret

```bash
helm template ./apps-of-apps/infra-stage-2 |kubectl apply -f -
watch -d 'kubectl -n argocd get applications'
```

At this stage stuff works. Set a new admin password and then go look at the web interface:

In another terminal

```bash
kubectl port-forward service/argocd-server -n argocd 8080:443
```

In original terminal

```bash
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

argocd login localhost:8080 --insecure --username admin --password $ARGOCD_PW
argocd account update-password --current-password $ARGOCD_PW
argocd login localhost:8080 --insecure --username admin # use new password

```

## To Do / Notes

- checked out viz dashboard via laptop
- will need to enforce the that the following annotation is on everything but cert-manager
  `linkerd.io/inject: enabled`
