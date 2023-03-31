#!/bin/bash
# Initialize master for topology with ONE master
# !!!
# !!! First create a ssh key on the master cp and get access to the other cps
# !!!

cd

# --- Setup configs for Kube API loadbalancer(Haproxy) ---

# use MASTER for one node and BACKUP for all other
STATE=MASTER
INTERFACE=eth0
ROUTER_ID=51
# 101 on MASTER 100 on BACKUP
PRIORITY=101
AUTH_PASS=42
APISERVER_VIP=ionos-k8s.jonasbe.de
APISERVER_DEST_PORT=6443
APISERVER_SRC_PORT=6443
HOST1_ID=jb-k8s-master-01
HOST1_ADDRESS=85.215.193.16

sudo mkdir /etc/keepalived
sudo echo "! /etc/keepalived/keepalived.conf
      ! Configuration File for keepalived
      global_defs {
          router_id LVS_DEVEL
      }
      vrrp_script check_apiserver {
        script "/etc/keepalived/check_apiserver.sh"
        interval 3
        weight -2
        fall 10
        rise 2
      }

      vrrp_instance VI_1 {
          state ${STATE}
          interface ${INTERFACE}
          virtual_router_id ${ROUTER_ID}
          priority ${PRIORITY}
          authentication {
              auth_type PASS
              auth_pass ${AUTH_PASS}
          }
          virtual_ipaddress {
              ${APISERVER_VIP}
          }
          track_script {
              check_apiserver
          }
      }" |sudo tee /etc/keepalived/keepalived.conf

sudo echo "#!/bin/sh

      errorExit() {
          echo "*** $*" 1>&2
          exit 1
      }

      curl --silent --max-time 2 --insecure https://localhost:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://localhost:${APISERVER_DEST_PORT}/"
      if ip addr | grep -q ${APISERVER_VIP}; then
          curl --silent --max-time 2 --insecure https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/"
      fi" |sudo tee /etc/keepalived/check_apiserver.sh

sudo mkdir /etc/haproxy
sudo echo "# /etc/haproxy/haproxy.cfg
      #---------------------------------------------------------------------
      # Global settings
      #---------------------------------------------------------------------
      global
          log /dev/log local0
          log /dev/log local1 notice
          daemon

      #---------------------------------------------------------------------
      # common defaults that all the 'listen' and 'backend' sections will
      # use if not designated in their block
      #---------------------------------------------------------------------
      defaults
          mode                    http
          log                     global
          option                  httplog
          option                  dontlognull
          option http-server-close
          option forwardfor       except 127.0.0.0/8
          option                  redispatch
          retries                 1
          timeout http-request    10s
          timeout queue           20s
          timeout connect         5s
          timeout client          20s
          timeout server          20s
          timeout http-keep-alive 10s
          timeout check           10s

      #---------------------------------------------------------------------
      # apiserver frontend which proxys to the control plane nodes
      #---------------------------------------------------------------------
      frontend apiserver
          bind *:${APISERVER_DEST_PORT}
          mode tcp
          option tcplog
          default_backend apiserver

      #---------------------------------------------------------------------
      # round robin balancing for apiserver
      #---------------------------------------------------------------------
      backend apiserver
          option httpchk GET /healthz
          http-check expect status 200
          mode tcp
          option ssl-hello-chk
          balance     roundrobin
              server ${HOST1_ID} ${HOST1_ADDRESS}:${APISERVER_SRC_PORT} check
              # [...]" |sudo tee /etc/haproxy/haproxy.cfg

sudo mkdir /etc/kubernetes/manifests
sudo echo "apiVersion: v1
      kind: Pod
      metadata:
        creationTimestamp: null
        name: keepalived
        namespace: kube-system
      spec:
        containers:
        - image: osixia/keepalived:2.0.17
          name: keepalived
          resources: {}
          securityContext:
            capabilities:
              add:
              - NET_ADMIN
              - NET_BROADCAST
              - NET_RAW
          volumeMounts:
          - mountPath: /usr/local/etc/keepalived/keepalived.conf
            name: config
          - mountPath: /etc/keepalived/check_apiserver.sh
            name: check
        hostNetwork: true
        volumes:
        - hostPath:
            path: /etc/keepalived/keepalived.conf
          name: config
        - hostPath:
            path: /etc/keepalived/check_apiserver.sh
          name: check
      status: {}" |sudo tee /etc/kubernetes/manifests/keepalived.yaml

sudo echo "apiVersion: v1
      kind: Pod
      metadata:
        name: haproxy
        namespace: kube-system
      spec:
        containers:
        - image: haproxy:2.1.4
          name: haproxy
          livenessProbe:
            failureThreshold: 8
            httpGet:
              host: localhost
              path: /healthz
              port: ${APISERVER_DEST_PORT}
              scheme: HTTPS
          volumeMounts:
          - mountPath: /usr/local/etc/haproxy/haproxy.cfg
            name: haproxyconf
            readOnly: true
        hostNetwork: true
        volumes:
        - hostPath:
            path: /etc/haproxy/haproxy.cfg
            type: FileOrCreate
          name: haproxyconf
      status: {}" |sudo tee /etc/kubernetes/manifests/haproxy.yaml

# ------

# --- Stacked ETCD Setup ---

# Update HOST0, HOST1 and HOST2 with the IPs of your hosts
export HOST0=85.215.193.16
export HOST1=85.215.238.10
export HOST2=85.215.160.29

# Update NAME0, NAME1 and NAME2 with the hostnames of your hosts
export NAME0="jb-k8s-master-01"
export NAME1="jb-k8s-master-02"
export NAME2="jb-k8s-master-03"

# Create temp directories to store files that will end up on other hosts
sudo mkdir -p /tmp/${HOST0}/ /tmp/${HOST1}/ /tmp/${HOST2}/

HOSTS=(${HOST0} ${HOST1} ${HOST2})
NAMES=(${NAME0} ${NAME1} ${NAME2})

for i in "${!HOSTS[@]}"; do
HOST=${HOSTS[$i]}
NAME=${NAMES[$i]}
sudo cat << EOF > /tmp/${HOST}/kubeadmcfg.yaml
# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: 'stable-1.25'
controlPlaneEndpoint: 'ionos-k8s.jonasbe.de:6443'
networking:
  podSubnet: '192.168.0.0/16'
etcd:
    local:
        serverCertSANs:
        - "${HOST}"
        peerCertSANs:
        - "${HOST}"
        extraArgs:
            initial-cluster: ${NAMES[0]}=https://${HOSTS[0]}:2380,${NAMES[1]}=https://${HOSTS[1]}:2380,${NAMES[2]}=https://${HOSTS[2]}:2380
            initial-cluster-state: new
            name: ${NAME}
            listen-peer-urls: https://${HOST}:2380
            listen-client-urls: https://${HOST}:2379
            advertise-client-urls: https://${HOST}:2379
            initial-advertise-peer-urls: https://${HOST}:2380
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
---
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
nodeRegistration:
  criSocket: 'unix:///var/run/containerd/containerd.sock'
      name: ${NAME}
localAPIEndpoint:
   advertiseAddress: ${HOST}
EOF
done

sudo kubeadm init phase certs etcd-ca

sudo kubeadm init phase certs etcd-server --config=/tmp/${HOST2}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-peer --config=/tmp/${HOST2}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST2}/kubeadmcfg.yaml
sudo kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST2}/kubeadmcfg.yaml
sudo cp -R /etc/kubernetes/pki /tmp/${HOST2}/
# cleanup non-reusable certificates
sudo find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete

sudo kubeadm init phase certs etcd-server --config=/tmp/${HOST1}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-peer --config=/tmp/${HOST1}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST1}/kubeadmcfg.yaml
sudo kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST1}/kubeadmcfg.yaml
sudo cp -R /etc/kubernetes/pki /tmp/${HOST1}/
sudo find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete

sudo kubeadm init phase certs etcd-server --config=/tmp/${HOST0}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-peer --config=/tmp/${HOST0}/kubeadmcfg.yaml
sudo kubeadm init phase certs etcd-healthcheck-client --config=/tmp/${HOST0}/kubeadmcfg.yaml
sudo kubeadm init phase certs apiserver-etcd-client --config=/tmp/${HOST0}/kubeadmcfg.yaml
# No need to move the certs because they are for HOST0

# clean up certs that should not be copied off this host
sudo find /tmp/${HOST2} -name ca.key -type f -delete
sudo find /tmp/${HOST1} -name ca.key -type f -delete



USER=k8s
HOST=${HOST1}
scp -r /tmp/${HOST}/* ${USER}@${HOST}:
ssh ${USER}@${HOST}
USER@HOST $ sudo -Es
root@HOST $ chown -R root:root pki
root@HOST $ mv pki /etc/kubernetes/

# ------



export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock

# Initialize
sudo kubeadm init --config kubeadm-config.yaml --upload-certs

# Set .kube config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Apply Pod Network
kubectl apply -f https://docs.projectcalico.org/archive/v3.24/manifests/calico-typha.yaml

# Installation following Calico docs:
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml