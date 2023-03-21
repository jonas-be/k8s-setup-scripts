#!/bin/bash

NEW_HOSTNAME="jb-k8s-master-01"
K8S_USER_PW="your-pw"

# Set Hostname
hostnamectl set-hostname $NEW_HOSTNAME
sed -i 's/debian/'$NEW_HOSTNAME'/g' /etc/hosts

# Add user IF PASSWORD IS WRONG SET USE "passwd k8s" TO RESET
useradd -m -p $(perl -e 'print crypt($ARGV[0], "password")' $K8S_USER_PW) -s /bin/bash -c "Kubernetes account, , , " k8s
usermod -aG sudo k8s

# Add SSH keys for k8s User
cd /home/k8s
mkdir /home/k8s/.ssh
cp ~/.ssh/authorized_keys /home/k8s/.ssh/
chown k8s:k8s /home/k8s/.ssh
chown k8s:k8s /home/k8s/.ssh/authorized_keys


# Update system
apt update && apt upgrade -y

# Install containerd
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install containerd.io -y

# Install kubelet, kubeadm, kubectl
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Now you have to initialize as a controll plane or join the cluster