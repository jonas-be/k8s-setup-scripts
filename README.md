# K8s setup scripts
This repository includes some bash scripts to set up a Kubernetes cluster.
The scripts are made for VMs only with debian installed.

> **Warning**
> The repo follows the [kubernetes docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).
> You should always check if some steps changed!
> Go through the [kubernetes docs](https://kubernetes.io) for official installation instructions.

> **Warning**
> You eventually have to Update versions!


## Requirements
 - Debian or Ubuntu
 - Access to root user

## Versions
Currently used Version in the scripts:
 - Kubernetes: stable-1.25
 - Containerd: version from [Docker download](https://download.docker.com/linux/)
 - Use [Calico](https://projectcalico.org) v3.24 as Pod network

## node-setup.sh
Setup everything to run Kubernetes control plane or worker

### What happens
 - Update system
 - Install [containerd](https://containerd.io)
 - Configure Kubernetes required stuff
 - Install
   - kubelet
   - kubeadm
   - kubectl

## initialize-one-control-plane.sh
Initialize control plane for topology with **ONE** control plane

### What happens
 - Create kubeadm-config.yaml
 - kubeadm init
 - Set .kube config
 - Apply pod network

## initialize-multiple-control-plane.sh
Initialize control plane for topology with **multiple** control planes

### What happens
- Create kubeadm-config.yaml
- kubeadm init
- Set .kube config
- Apply pod network