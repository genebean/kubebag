Vagrant.configure("2") do |config|
  config.vm.box = "genebean/centos-7-puppet-latest"

  # this controls how many nodes are created
  node_num=1

  (1..node_num).each do |i|
    if i == 1 then
      vm_name="master"
    else
      vm_name="node#{i-1}"
    end

    config.vm.define vm_name do |s|
      s.vm.hostname=vm_name
      s.vm.network "private_network", ip: "192.168.50.#{i+10}"
      s.vm.provision "shell", inline: 'echo "GATEWAYDEV=eth0" >> /etc/sysconfig/network && systemctl restart network'
      s.vm.provision "shell", inline: 'yum install -y policycoreutils-python'
      if i == 1 then
        s.vm.provider "virtualbox" do |v|
          v.memory = 4096
          v.cpus = 2
        end

        # For Master
        s.vm.provision "shell", inline:<<-SHELL
          # Store private network IP address in variable
          IPADDR=$(ip a show eth1 | grep "inet " | awk '{print $2}' | cut -d / -f1)
        
          # Deploy k3s, specify private IP as kubelet's IP, disable loadbalancer and traefik
          curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy=servicelb --no-deploy=traefik --node-ip=${IPADDR} --flannel-iface=eth1 --write-kubeconfig-mode 644" sh -
        
          # Place token for agent registration in shared folder
          cp /var/lib/rancher/k3s/server/node-token /vagrant/token
        
          # make sure the kube config is found
          echo "export KUBECONFIG='/etc/rancher/k3s/k3s.yaml'" > /etc/profile.d/k3s-kubeconfig.sh
          source /etc/profile.d/k3s-kubeconfig.sh
          cat $KUBECONFIG |sed 's/default/k3s/g' |sed 's/127\.0\.0\.1/192.168.50.11/' > /vagrant/kubeconfig
          
          # install helm
          export PATH=/usr/local/bin:$PATH
          curl -L https://git.io/get_helm.sh | bash
          kubectl -n kube-system create sa tiller \
            && kubectl create clusterrolebinding tiller \
            --clusterrole cluster-admin \
            --serviceaccount=kube-system:tiller
          helm init --skip-refresh --upgrade --service-account tiller          
        
          # OpenFaaS uses the shasum program
          yum install -y perl-Digest-SHA

          # sleep so tiller can be started up
          echo 'sleep so tiller can get started up...'
          sleep 60

          # deploy stuff
          /vagrant/do-deploys.sh
        SHELL
      else
        # For Nodes
        s.vm.provision "shell", inline:<<-SHELL
          export K3S_TOKEN=$(cat /vagrant/token)
          export K3S_URL=https://192.168.50.11:6443
        
          # Store private network IP address in variable
          IPADDR=$(ip a show eth1 | grep "inet " | awk '{print $2}' | cut -d / -f1)
        
          curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=${IPADDR} --flannel-iface=eth1" sh -
        SHELL
      end
    end
  end
end

