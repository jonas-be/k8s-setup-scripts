#!/bin/bash
# Initialize master for topology with ONE master

cd

# Config
#   USE: "--config kubeadm-config.yaml" IN "kubeadm init"
echo '# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: "stable-1.25"
controlPlaneEndpoint: "ionos-k8s.jonasbe.de:6443"
networking:
  podSubnet: "192.168.0.0/16"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
---
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
nodeRegistration:
  criSocket: "unix:///var/run/containerd/containerd.sock"' |tee kubeadm-config.yaml



export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock

# Initialize
kubeadm init --config kubeadm-config.yaml --upload-certs

# Set .kube config
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Apply Pod Network
kubectl apply -f https://docs.projectcalico.org/archive/v3.24/manifests/calico-typha.yaml

# Installation following Calico docs:
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml


# Join control planes and workers with the commands provided in the kubeadm init step