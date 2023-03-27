#!/bin/bash
# Initialize master for topology with ONE master

cd

# use MASTER for one node and BACKUP for all other
STATE=BACKUP
INTERFACE=eth0
ROUTER_ID=51
# 101 on MASTER 100 on BACKUP
PRIORITY=100
AUTH_PASS=42
APISERVER_VIP=ionos-k8s.jonasbe.de
APISERVER_DEST_PORT=6443
APISERVER_SRC_PORT=6443
HOST1_ID=jb-k8s-master-02
HOST1_ADDRESS=85.215.238.10

mkdir /etc/keepalived
echo "! /etc/keepalived/keepalived.conf
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
      }" |tee /etc/keepalived/keepalived.conf

echo "#!/bin/sh

      errorExit() {
          echo "*** $*" 1>&2
          exit 1
      }

      curl --silent --max-time 2 --insecure https://localhost:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://localhost:${APISERVER_DEST_PORT}/"
      if ip addr | grep -q ${APISERVER_VIP}; then
          curl --silent --max-time 2 --insecure https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/"
      fi" |tee /etc/keepalived/check_apiserver.sh

mkdir /etc/haproxy
echo "# /etc/haproxy/haproxy.cfg
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
              # [...]" |tee /etc/haproxy/haproxy.cfg

mkdir /etc/kubernetes/manifests
echo "apiVersion: v1
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
      status: {}" |tee /etc/kubernetes/manifests/keepalived.yaml

echo "apiVersion: v1
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
      status: {}" |tee /etc/kubernetes/manifests/haproxy.yaml



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

echo ""
echo ""
echo ""
echo "--- DONE ---"
echo ""
echo "Now join as ControlPlane. Use the command from master ControlPlane!"