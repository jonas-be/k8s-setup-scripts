#!/bin/bash

cd

# Configure cgroup
#   PLEASE USE: "--config kubeadm-config.yaml" IN "kubeadm init"
echo '# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: latest
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
---
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"' |tee kubeadm-config.yaml

# Initialize
sudo kubeadm init \
  --config kubeadm-config.yaml
#  --control-plane-endpoint

# Set .kube config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Apply Pod Network
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

sudo mkdir -p /opt/cni/bin
curl -O -L https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
sudo tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.2.0.tgz