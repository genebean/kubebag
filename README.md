# Kubebag

Kubebag is my playground where I am learning about k8s by trying to create a Kubernetes-based setup that could replace my current traditional server. The highlights of what I am aiming for:

- [x] Based on k3s
- [x] MetalLB
- [x] local-path-provisioner
- [x] Deployments with Argo CD
- [x] Nginx Ingress controller
- [x] OpenFaaS
- [ ] Jekyll via OpenFaaS
- [ ] Slack bot via OpenFaaS
- [ ] WordPress x2
- [ ] MariaDB
- [ ] Matomo
- [ ] Prometheus
- [ ] Alertmanager
- [x] external-dns
- [ ] cert-manager
- [ ] Linkerd 2
- [ ] Loki & promtail (maybe)

To support this running in Vagrant before being run for real a few additional tools are being deployed here:

- [x] Addresses that utilize [nip.io](https://nip.io/)
- [x] CoreDNS
- [ ] step-ca (a stand-in for Let's Encrypt)
- [ ] Grafana (in production I plan to use Grafana Cloud)

## Running Kubebag

### Starting it up

The initial setup utilizes sync waves to setup infrastructure in the order its needed:

1. local-path-provisioner
2. MetalLB
3. Nginx Ingress
4. Argo CD
5. everything else

The setup process will copy the generated kubeconfig `/vagrant`, aka the project folder on your computer, and edit it so that it will work as needed. The process installs k3s and Argo CD and then deploys "applications" via a local Helm chart. The process takes a few minutes to run. The kubeconfig at the end of the block below will let you know when you can connect to Argo CD.

```bash
cd kubebag
export KUBECONFIG=kubeconfig
vagrant up && kubectl get services -n nginx-ingress -w
```

Once you see a line like the one below you can hit `^c` and connect to [argocd.192.168.50.240.nip.io](http://argocd.192.168.50.240.nip.io)

```bash
NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                      AGE
nginx-ingress-controller        LoadBalancer   10.43.176.66    192.168.50.240   80:30394/TCP,443:32516/TCP   7h45m
```

The username is `admin` and you can get the password by running `cat argocd-pw` from your terminal. Once you connect you may want to "sync" the application named `argocd`.

### OpenFaaS

You can connect to OpenFaaS via [openfaas.192.168.50.240.nip.io](http://openfaas.192.168.50.240.nip.io). The username is `admin` and the password is `functions-are-fun` (these are set [here](configs/openfaas/values.yaml))

### Testing external-dns & CoreDNS

If you want to verify that these services are working run the following commands:

```bash
$ kubectl apply -f test-files/localdns-tester-ingress.yaml
ingress.extensions/nginx created

$ kubectl get ingress --all-namespaces
NAMESPACE   NAME                    HOSTS                            ADDRESS          PORTS   AGE
argocd      argocd-server-ingress   argocd.192.168.50.240.nip.io     192.168.50.240   80      8h
openfaas    openfaas-ingress        openfaas.192.168.50.240.nip.io   192.168.50.240   80      8h
default     nginx                   nginx.vagrant.example.com        192.168.50.240   80      8m

$ kubectl get -n localdns service/localdns-coredns
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
localdns-coredns   ClusterIP   10.43.61.184   <none>        53/UDP,53/TCP   49m
```

The above set of commands applies a sample ingress rule, verifies it is registered, and then looks up the ip of the CoreDNS server. Once you have that info you are ready to test querying that server like so:

```bash
$ kubectl run -it --rm --restart=Never --image=infoblox/dnstools:latest dnstools
If you don't see a command prompt, try pressing enter.

dnstools# dig @10.43.61.184 +short nginx.vagrant.example.com
192.168.50.240

dnstools# exit
pod "dnstools" deleted
```

This brings up a temporary container for testing. Be sure to use the IP shown in your commands, not the one from here. After typing `exit` the pod for the test container is deleted. Now you can clean up the test ingress by running this:

```bash
$ kubectl delete -f test-files/localdns-tester-ingress.yaml
ingress.extensions "nginx" deleted
```

Assuming the above commands all worked, you now have a functional external-dns setup registering ingresses from your k3s instance with a DNS server external to the automated bits of Kubernetes. Note, though, that only ingresses are registered and then only if they are in the `vagrant.example.com` domain.
