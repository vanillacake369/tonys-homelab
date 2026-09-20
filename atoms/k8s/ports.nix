# Kubernetes service ports shared by NixOS role modules.
let
  ports = {
    apiServer = 6443;
    etcdClient = 2379;
    etcdPeer = 2380;
    kubelet = 10250;
    kubeScheduler = 10251;
    kubeControllerManager = 10252;
  };
in
  ports
  // {
    masterTcp = [
      ports.apiServer
      ports.etcdClient
      ports.etcdPeer
      ports.kubelet
      ports.kubeScheduler
      ports.kubeControllerManager
    ];

    workerTcp = [
      ports.kubelet
    ];
  }
