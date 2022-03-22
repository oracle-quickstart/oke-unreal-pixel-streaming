# Unreal Pixel Streaming on OKE

This project represents a container-based Pixel Streaming runtime on Oracle
Container Engine for Kubernetes (OKE)

- [Unreal Pixel Streaming on OKE](#unreal-pixel-streaming-on-oke)
  - [About WebRTC](#about-webrtc)
  - [Cluster Setup](#cluster-setup)
    - [Default Node Pool](#default-node-pool)
    - [Turn Node Pool](#turn-node-pool)
    - [GPU Node Pool](#gpu-node-pool)
    - [Dependencies](#dependencies)
  - [Demo](#demo)
  - [Image Build](#image-build)
    - [Service Layers](#service-layers)
    - [Pixel Streaming Build](#pixel-streaming-build)
  - [Custom Deploy](#custom-deploy)
  - [Telemetry](#telemetry)
    - [Install Prometheus Stack](#install-prometheus-stack)
    - [Add DCGM Exporter](#add-dcgm-exporter)
    - [Access Grafana](#access-grafana)
  - [Scaling](#scaling)
    - [Prometheus Adapter](#prometheus-adapter)
    - [Streamer HPA](#streamer-hpa)
  - [Assumptions and Limitations](#assumptions-and-limitations)
    - [GPU Allocation](#gpu-allocation)
    - [TODOs](#todos)
  - [References](#references)

## About WebRTC

WebRTC defines a web peering technology for real-time media and data streaming.
To establish the peer-to-peer connection, WebRTC uses a four-way handshake where
the various peer networking configurations and firewalls are traversed. The basic
design of a WebRTC system includes the following:

- A **signalling** service that establishes an initial connection with the streaming application and exchanges **Interactive Connectivity Establishment** (ICE) candidate configurations.
- Session Traversal Utilities for NAT (STUN) and Traversal Using Relays around NAT (TURN) servers which
provide ICE candidates to the signal service
- A Session Description Protocol network path is discovered through ICE negotiation and the peer-to-peer connection is created.
- STUN/TURN server transports the encoded media stream between the streaming app and browser.

## Cluster Setup

There are three distinct node pools to use in this setup. Specifics regarding
node shape are suggested as baseline starting points, and can be customized by
requirements.

| Name                          | Description                                          | Node Shape            | Node Count |
| ----------------------------- | ---------------------------------------------------- | --------------------- | ---------- |
| [Default](#default-node-pool) | General cluster workloads                            | `VM.Standard.E4.Flex` | 3+         |
| [Turn](#turn-node-pool)       | Deploy `coturn` as DaemonSet with host networking    | `VM.Standard.E4.Flex` | 1+         |
| [GPU](#gpu-node-pool)         | PixelStreaming runtime with signal server as sidecar | *                     | 1+         |

> `*` Specific GPU shape can also vary depending on the application and scaling demands.
It is recommended to evaluate performance and settings accordingly.

### Default Node Pool

The default (or general) node pool is considered for multipurpose installations
or cluster-wide resources such as ingress controller, telemetry services,
applications, etc.

For purposes of this example, the standard _Quick Create_ workflow with public API
and private workers is considered adequate. Select alternatives, or customize as
necessary.

> Once created, note that the worker node subnet will have a `10.0.10.0/24` CIDR range.

> `*` Specific GPU shape can also vary depending on the application and scaling demands.
It is recommended to evaluate performance and settings accordingly.

### Turn Node Pool

This node pool is used exclusively for the STUN/TURN services running [coturn][coturn].
While coTURN is the most prevalent suggestion for hosting our own TURN services, alternates
like [Pion TURN][pion-turn] may be viable.

> `STUN` and `TURN` are network bound services, so specific attention to network bandwidth
> and associative compute sizing should be considered.

For public access, the nature of STUN/TURN dictates that the node pool is created
in a public subnet, with associative security list rules and a public route table
to work within OKE. In order to leverage host networking, the services are run
as a DaemonSet on this specific node pool. These following setup used to acheive
a single node deployment:

1. Create a public subnet (regional) in the OKE cluster VCN. (This example used `10.0.30.0/24` CIDR block)
1. Assign default DHCP options for cluster vcn
1. Assign the public route table to the public subnet (default from OKE is fine)
1. Assign/update the _existing_ **node** security list for the TURN subnet CIDR block
  
    | Dir     | Source/Dest    | Protocol      | Src Port | Dest Port   | Type/Code | Description                                                             |
    | ------- | -------------- | ------------- | -------- | ----------- | --------- | ----------------------------------------------------------------------- |
    | Ingress | `10.0.30.0/24` | All Protocols | *        | *           |           | Allow pods on turn nodes to communicate with pods on other worker nodes |
    | Egress  | `10.0.30.0/24` | All Protocols | *        | *           |           | Allow pods on turn nodes to communicate with pods on other worker nodes |
    | Ingress | `0.0.0.0/0`    | TCP           | *        | 3478        |           | STUN TCP                                                                |
    | Ingress | `0.0.0.0/0`    | UDP           | *        | 3478        |           | TURN UDP                                                                |
    | Ingress | `0.0.0.0/0`    | TCP           | *        | 49152-65535 |           | STUN Connection ports                                                   |
    | Ingress | `0.0.0.0/0`    | UDP           | *        | 49152-65535 |           | TURN Connection ports                                                   |

1. Update K8s API endpoint security list to include ingress/egress to the turn CIDR block

    | Dir     | Source/Dest    | Protocol | Src Port | Dest Port | Type/Code | Description                      |
    | ------- | -------------- | -------- | -------- | --------- | --------- | -------------------------------- |
    | Ingress | `10.0.30.0/24` | TCP      | *        | 6443      |           | turn worker to k8s API endpoint  |
    | Ingress | `10.0.30.0/24` | TCP      | *        | 12250     |           | turn worker to OKE control plane |
    | Ingress | `10.0.30.0/24` | ICMP     |          |           | 3, 4      | path discovery turn              |
    | Egress  | `10.0.30.0/24` | ICMP     |          |           | 3, 4      | path discovery turn              |
    | Egress  | `10.0.30.0/24` | TCP      | *        | *         |           | TURN traffic from worker nodes   |
  
1. Create the node pool using **Advanced Options** to specify additional k8s key-value labels:

    ```text
    app.pixel/turn=true
    ```

1. Taint each node after they start to ensure selective node assignment/affinity

    ```sh
    # assuming node pool was labeled with 'app.pixel/turn=true' in provisioning
    kubectl taint nodes $(kubectl get nodes -l app.pixel/turn=true --no-headers | awk '{print $1}') app.pixel/turn=true:NoSchedule
    ```

    > NOTE: this is done automatically as part of the `turn` DaemonSet

### GPU Node Pool

This is the node pool for the Pixel Streaming GPU workloads. Part of the design,
each Pixel Streaming runtime is directly asosciated with a corresponding node.js
signal server known as "cirrus" (`./signalserver` here). As such, each pixel streaming
container runs with cirrus as a sidecar on the same pod.

It is necessary to differentiate the GPU pool from others with a kubernetes label.
Create the node pool using **Advanced Options** to specify additional k8s labels:

```text
app.pixel/gpu=true
```

> Read more on this under [GPU Allocation](#gpu-allocation)

The architecture used here for pixel streaming does not require any specific
network/subnet other than the general OKE node subnet

### Dependencies

As with many kubernetes systems, there are several choices for anciliary services
such as ingress controllers, certificate management, metrics, etc.. This solution
aims to offer viability using the most basic/standard dependencies:

- Ingress Controller: [documentation](https://kubernetes.github.io/ingress-nginx/deploy/)

    ```sh
    helm upgrade --install ingress-nginx ingress-nginx \
      --repo https://kubernetes.github.io/ingress-nginx \
      --namespace ingress-nginx --create-namespace 
    ```

- Cert Manager: [documentation](https://cert-manager.io/docs/installation/helm/)

    1. Install CRDs (if not already installed)

        ```sh
        kubectl apply -f \
          https://github.com/jetstack/cert-manager/releases/download/v1.6.0/cert-manager.crds.yaml
        ```

    1. Install chart

        ```sh
        helm upgrade --install cert-manager cert-manager \
          --repo https://charts.jetstack.io \
          --namespace cert-manager --create-namespace \
          --version v1.6.0
        ```

    1. Create associative `ClusterIssuer` or `Issuer` resources depending on needs. As an example:

        ```sh
        # adjust as needed
        kubectl apply -f ./support/misc/issuer.yaml
        ```

- Metrics Server: [documentation](https://artifacthub.io/packages/helm/metrics-server/metrics-server)

    1. Install chart

        ```sh
        helm upgrade --install metrics-server metrics-server \
          --repo https://kubernetes-sigs.github.io/metrics-server/ \
          --namespace metrics --create-namespace
        ```

## Demo

Prebuilt images are included with this repo, along with a demo
Pixel Streaming image. With a cluster configured per the instructions
above, you can deploy the entire runtime with the following:

```sh
kubectl create ns demo
kubectl apply -f demo.yaml
```

> See [demo.yaml](./demo.yaml) for complete details

## Image Build

All of the services/constructs are contained within this repo with the exception
of the Unreal project source code. See more on this [below](#pixel-streaming-build).

### Service Layers

As a convenience all service images can be built with the following command:

```sh
# from project root
docker compose build -f ../docker-compose.yml
```

Each service image should be built and pushed to the respective `OCIR` registy. Image tags
can be found in the [./k8s/kustomization.yaml](./k8s/kustomization.yaml) file, however any
tag name can be used, so long as it's repo/tag is known prior to deployment.

### Pixel Streaming Build

For this piece, an example `Dockerfile` is provided in the [unreal](../unreal/Dockerfile) directory.

In this example, it is expected that the `./project` relative path contains the
full project source, which would be `./project/PixelStreamingDemo.uproject` in
this case - update as necessary.

> **NOTE** Access to the [official](https://unrealcontainers.com/docs/obtaining-images/official-images) Unreal Engine docker images
(hosted on `ghcr.io/epicgames/unreal-engine`) is restricted, so it is necessary
to sign up and register for access. Instructions are [here](https://github.com/EpicGames/Signup)

Once repo access is obtained, the basic build process is as follows:

1. Authenticate to [`ghcr`](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry)

1. Build the unreal project

    ```sh
    # change to the project directory containing dockerfile described above
    cd path/to/ue4/project
    # docker build (in current directory '.')
    docker build -t my-pixelstream:latest .
    ```

1. Tag and push to OCIR per [documentation](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm).

## Custom Deploy

Although we've used `helm` to install various objects in the kubernetes environment,
this Pixel Streaming demo deployment is designed using plain
`kubectl` and [`kustomize`](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) commands directly to de-mystify the k8s manifests in our runtime
, offering higher transparency to the readers :).

1. As a first step, create a namespace for our application and it's respective systems

    ```sh
    export NAMESPACE=pixel
    kubectl create ns $NAMESPACE
    ```

2. Create an OCIR registry secret (refer to [documentation](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm))

    ```sh
    kubectl create secret docker-registry ocirsecret \
      --docker-server=<region-key>.ocir.io \
      --docker-username='<tenancy-namespace>/<oci-username>' \
      --docker-password='<oci-auth-token>' \
      --docker-email='<email-address>' \
      --namespace $NAMESPACE
    ```

3. Optionally locate an ingress controller ip address for use of a wilcard dns name from [nip.io](https://nip.io)

    ```sh
    # get public ip address
    kubectl get svc -A | grep ingress | grep LoadBalancer | awk '{print $5}' | head -n 1
    # or use a hex format
    printf '%02x' $(kubectl get svc -A | grep LoadBalancer | grep ingress-nginx | awk '{print $5}' | head -n 1 | tr '.' ' '); echo
    ```

    > Set the ip dns name in `.env` below

4. Create a `.env` file in this directory or set environment
   with configuration variables like the following:

    ```sh
    # kubernetes namespace for pixel streaming
    NAMESPACE=pixel
    # container registry/repo path
    REPO=iad.ocir.io/mytenancy/pixeldemo
    # container registry secret (optional)
    REPO_SECRET=
    # tag version (all services use same)
    IMAGE_TAG=latest
    # unreal image container registry
    UNREAL_REPO=iad.ocir.io/mytenancy/pixeldemo
    # name of the unreal container in OCIR 
    UNREAL_IMAGE_NAME=my-pixelstream
    # unreal container registry secret (optional)
    UNREAL_REPO_SECRET=
    # version for the streamer image (can differ from the services)
    UNREAL_IMAGE_TAG=latest
    # a hostname to use (nip.io ip example)
    INGRESS_HOST=my-pixelstream.<load balancer ip>.nip.io
    # optionally specify ingress path prefix (example: /game)
    INGRESS_PATH=
    # specify initial TURN service username
    TURN_USER=userx0000
    # also specify a turn password
    TURN_PASS=passx1111
    # specify whether or not to enable the pod proxy
    PROXY_ENABLE=false
    # configure proxy prefix
    PROXY_PATH_PREFIX=/proxy
    # configure basic auth users (unreal/demo) https://doc.traefik.io/traefik/middlewares/http/basicauth/
    PROXY_AUTH_USERS=
    ```

5. Use the [./configure.sh](./configure.sh) wrapper to generate a `kustomization`
   overlay and (optionally) apply:

    ```sh
    # run to generate ./overlay and output manifests 
    ./configure.sh
    # run to generate ./overlay and output manifests with different env path
    ./configure.sh path/to/.env 
    # generate ./overlay AND apply the manifests
    ./configure.sh | kubectl apply -f -
    ```

    > **NOTE** to delete, just run `./configure.sh | kubectl delete -f -`

6. Inspect objects created in the cluster on `pixel` namespace

    ```sh
    kubectl get all -n pixel
    ```

7. Checkout the traefik proxy dashboard

    ```sh
    kubectl -n pixel port-forward service/router 8080
    ```

    > Open http://localhost:8080/dashboard/#/http/routers

## Telemetry

GPU Telemetry is done through the use of prometheus and the DCGM exporter. Setup and configuration
details can be found in the [NVIDIA Documentation][nvidia-gpu-telemetry]

### Install Prometheus Stack

A [values](./support/prometheus.values.yaml) file for the `prometheus` stack is provided
with settings to include GPU metrics from `dcgm-exporter`. These values
are unmodified from the [nvidia installation guide][nvidia-gpu-telemetry]

```sh
helm upgrade --install prometheus-stack kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --namespace prometheus --create-namespace \
  --values ./support/prometheus.values.yaml \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### Add DCGM Exporter

Although prometheus has been installed, it won't collect any GPU metrics until
the **Data Center GPU Manager** exporter is deployed which exposes the metrics endpoint
scraped by prometheus. Again, a custom [values](./support/dcgm.values.yaml) file is defined
to ensure the DaemonSet is properly deployed on GPU nodes.

```sh
helm upgrade --install dcgm-exporter dcgm-exporter \
  --repo https://nvidia.github.io/dcgm-exporter/helm-charts \
  --namespace prometheus \
  --values ./support/dcgm.values.yaml
```

The values applied for this helm chart release are specific to this use case:

```yaml
# Establish known gpu node selections
nodeSelector:
  app.pixel/gpu: "true"

# ensure scheduling is allowed based on OKE GPU node taints
tolerations:
  - key: "nvidia.com/gpu"
    effect: "NoSchedule"
    operator: "Exists"
```

### Access Grafana

Grafana is installed automatically as part of the `kube-prometheus-stack` chart.
The installation is pre-loaded with several useful kubernetes dashboards. In order
to see GPU metrics, we'll add a dashboard related specifically to the `dcgm-exporter`
metrics.

1. Get the grafana `admin` password:

    ```sh
    kubectl get secret prometheus-stack-grafana \
      -n prometheus \
      -o jsonpath="{.data.admin-password}" | base64 --decode; echo
    ```

    > The `admin` account password defaults to `prom-operator` in the prometheus helm chart

1. In order to access the grafana user interface, you can enable ingress
through the `kube-prometheus-stack` `grafana` settings or define it separately.

    - Based on the prometheus installation, the grafana service will be named
    `prometheus-stack-grafana`. For now, simply open a local port-forward on to the service
    and load the dashboard.

        ```sh
        kubectl port-forward svc/prometheus-stack-grafana -n prometheus 8000:80
        ```

    - Open [localhost:8000](http://localhost:8000) and use the admin credentials found above.

1. Once Grafana is opened, import relevant dashboards:

   1. Custom pixel streaming dashboard included as [json](./support/grafana/pixel-streaming-dashboard.json)
   2. [DCGM exporter dashboard][dcgm-exporter-dashboard] for overall GPU metrics

## Scaling

### Prometheus Adapter

In order to acheive the desired autoscaling scenario of reactive
scaling the GPU streaming application, it is necessary
to leverage the [Prometheus Adapter](https://github.com/kubernetes-sigs/prometheus-adapter) with custom metrics on the streamer Horizontal Pod Autoscaler.

Each signal server produces a metric that indicates whether or not (1 or 0)
its stream is allocated to a client. By scaling on this metric with a target
total value of `1`, the replicaset will be adjusted to hit this goal. It's worth
noting that the GPU pool/shape should be chosen such that cluster autoscaling
happens infrequently enough as not to impact the user experience.

Install the prometheus adapter:

```sh
helm upgrade --install prometheus-adapter prometheus-adapter \
  --repo https://prometheus-community.github.io/helm-charts \
  --namespace prometheus \
  --values ./support/prometheus-adapter.values.yaml
```

> See the custom [values](./support/prometheus-adapter.values.yaml) for
the custom metric configurations

Test the custom metrics:

```sh
# average player connections
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/pixel/pods/*/stream_player_connections' | jq .
# total free streams
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/pixel/services/*/pixelstream_available_count' | jq .
# ratio of number of players (channels) to streams
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/pixel/services/*/player_stream_pool_ratio' | jq .
```

### Streamer HPA

With the Prometheus Adapter deployed, custom metrics are used to establish horizontal pod autoscaling on the streaming app deployment.
Using the `player_stream_pool_ratio`, the following target logic applies:

- A value of `1` adjusts so that the number of players should equal the number of streams.
- A value `< 1` (such as 900m) means that streams increase proactively to accommodate future player sessions

> Refer to [stream-hpa.yaml](./base/streaming/stream-hpa.yaml) for the full specification.

Scaling down applies the heuristic notion [`pod-deletion-cost`](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/#pod-deletion-cost) for replicaset scaling order/preference. Note that this feature requires Kubernetes `1.22` or later. Without this, active pods (with connected players) may be terminated indiscriminately.

Once the total number of requested pods exceeds available cluster resources, it is necessary to configure Cluster Autoscaling. Refer to this [guide][cluster-autoscaling] for details.

## Assumptions and Limitations

This architecture is partially based on original sample code from Epic Games
to support Unreal Engine Pixel Streaming (signalserver and matchmaker).
There are some associated limitations with those services, many of which are
described [here](https://tensorworks.com.au/blog/an-open-architecture-for-scalable-pixel-streaming/),
as well as some introduced by this design. This section is meant to call attention
to some known shortcomings that may require additional work.

- Authentication is not included. Users should consider adding upstream auth,
  or extending the [router](../src/router/) configurations.
- Streamer availability is done via broadcast to matchmaker rather than using
  service discovery from endpoints.
- Player websocket connections are queued through matchmaker and forwarded to
  matched streams.
- Matchmaker replicas do not share state, therefore stream availability and
  player session affinity may be unpredictable.
- Each WebRTC session establishes a peer-to-peer mesh, so the number of
  connections is n<sup>2</sup> where `n` is the number of participants.
- The static browser code in [`src/player`](../src/player/) is mostly original,
  but slightly adapted for this runtime. It is meant purely as a starting point,
  however is not a model for modern web apps.
- The demo applies some defaults to the pixel streaming runtime, including
  a maximum 30 frames per second value. This is an arbitrary selection for demo
  performance, and may be adjusted in the env [ConfigMap](./base/streaming/config/pixel.properties).
  Refer to [documentation](https://docs.unrealengine.com/4.27/en-US/SharingAndReleasing/PixelStreaming/PixelStreamingReference/).

### GPU Allocation

- Containers (and Pods) _normally_ do not share GPUs - as in, there's no
  overcommitting of GPUs. Each container can request one or more GPUs, but it
  is not possible to request a fraction of a GPU.
  - This demo uses the `app.pixel/gpu` label for affinity and proportionate CPU requests to
    allow more than one stream on a single GPU, which may not be suitable in production.
    > See [stream-runtime.yaml](./base/streaming/stream-runtime.yaml#L125) for more information.
- [MIG Support][mig-k8s] (multi-instance GPU partitioning) will require testing with A100 shapes,

### TODOs

- Add STUN/TURN metrics and define approach for autoscaling
- Revisit autoscale (nodes and pods) based on GPU availability and app design
- Define a k8s service for the streamer, allowing matchmaker (or similar) to
  perform endpoint discovery and manage player affinity
- Support distributed matchmaker state (with `redis` for example) to widen
  the player-to-stream broker system

## References

Below is a list of helpful references with concepts applied within this
architecture

| Link                                                                                                                 | About                                                                                                                                        |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| [TURN servers for cloud](https://devblogs.microsoft.com/cse/2018/01/29/orchestrating-turn-servers-cloud-deployment/) | has some good information about `coturn` in docker                                                                                           |
| [GCP WebRTC + GPU](https://cloud.google.com/architecture/orchestrating-gpu-accelerated-streaming-apps-using-webrtc)  | perhaps the holy grail of related examples. It does not relate to pixel streaming, but much of the architecture is derived from this example |
| [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/)                              | Tests STUN/TURN                                                                                                                              |
| [Pion TURN][pion-turn]                                                                                               | Alternate to `coturn`                                                                                                                        |
| -                                                                                                                    |                                                                                                                                              |
| [UE4 Containers](https://docs.unrealengine.com/4.27/en-US/SharingAndReleasing/Containers/ContainersOverview/)        | Unreal Engine official docs on general container usage                                                                                       |
| [unrealcontainers.com](https://unrealcontainers.com/docs/use-cases/pixel-streaming)                                  | resource created by Adam Rehn - AKA God of Unreal running in Linux/Containers                                                                |
| [Unreal Engine Images](https://github.com/orgs/EpicGames/packages/container/unreal-engine/versions)                  | requires permissions with Epic Games, but this is where the `ghcr.io` base images from Unreal live                                           |
| [Unreal Image EULA](https://unrealcontainers.com/docs/obtaining-images/eula-restrictions)                            | Information on how Unreal Engine EULA restricts the distribution of Unreal Engine container images                                           |
| -                                                                                                                    |                                                                                                                                              |
| [NVIDIA containers][nvidia-containers]                                                                               | Information from NVIDIA on GPUs in cloud native                                                                                              |
| [NVIDIA GPU Monitoring][nvidia-gpu-telemetry]                                                                        | How to collect GPU metrics for prometheus in k8s (Data Center GPU Metrics exporter)                                                          |
| [GPU Monitoring Tools][gpu-monitoring-tools]                                                                         | Helm charts for GPU Telemetry                                                                                                                |
| [MIG Support][mig-k8s]                                                                                               | Multi-instance GPU partitioning support (NVIDIA A100)                                                                                        |
| [Oracle GPU](https://www.oracle.com/cloud/partners/gpu.html)                                                         | Oracle Cloud Infrastructure NVIDIA GPU Instances                                                                                             |

<!-- links -->
[mig-k8s]:https://docs.nvidia.com/datacenter/cloud-native/kubernetes/mig-k8s.html
[nvidia-containers]:https://docs.nvidia.com/datacenter/cloud-native/
[nvidia-gpu-telemetry]:https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/dcgm-exporter.html#gpu-telemetry
[gpu-monitoring-tools]:https://nvidia.github.io/gpu-monitoring-tools/

[coturn]:https://github.com/coturn/coturn
[pion-turn]:https://github.com/pion/turn
[dcgm-exporter-dashboard]:https://grafana.com/grafana/dashboards/12239
[cluster-autoscaling]:https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingclusterautoscaler.htm