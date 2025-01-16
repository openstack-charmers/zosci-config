# Deploy Zuul CI, MariaDB, and Apache Zookeeper

This repo contains a [Terraform](https://www.terraform.io) plan and
configuration files you can use to deploy [Zuul CI](zuul-ci.org/) 9.1 and its
dependencies - [MariaDB](https://mariadb.com) and [Apache
Zookeeper](https://zookeeper.apache.org/) - to
[Kubernetes](https://kubernetes.io) using [the Kubernetes Terraform
provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest).


## Deployment


1. Deploy a Kubernetes cluster on top of a OpenStack cloud.

``` bash
juju deploy ./kubernetes-core/bundle.yaml
```

2. Get the kubeconfig file

``` bash
juju run-action \
    --format json \
    --wait \
    kubernetes-control-plane/leader get-kubeconfig \
    | jq -r '.[]|.results.kubeconfig' > kubeconfig

```

3. Run the terraform plan
``` bash
terraform init
terraform apply
```

## Variables

The terraform plan offers the following variables to be overridden:

| Name               | Default Value              | Description                                     |
|--------------------|----------------------------|-------------------------------------------------|
| kubeconfig         | ~/.kube/config             | Path to kubectl configuration file              |
| storage_class_name | csi-cinder-default         | Storage class name to use when creating volumes |
| docker-username    |                            | Dockerhub username                              |
| docker-password    |                            | Dockerhub password (or token)                   |
| docker-server      | https://index.docker.io/v1 | Dockerhub server                                |
| docker-email       |                            | Dockerhub email                                 |


## Images

Nodepool needs to be configured with the images that will be used to create
instances with, a common Charmed OpenStack cloud will be deployed using
glance-simplestreams-sync making Ubuntu images available although they will be
rotated automatically by default too, so it's better to make copies of the
images that will be used by nodepool.

Run [tools/copy-images.sh](./tools/copy-images.sh)

## FAQ

### Accessing Zuul Web (via kube-proxy)

In the bastion that has access to the k8s cluster create a proxy to zuul-web on port 9000

``` bash
kubectl -n zuul port-forward --address 0.0.0.0 $(kubectl get pods -n zuul | grep zuul-web | awk '{print $1}') 9001:9000
```

Then in your machine when you have SSH access to the bastion run:

``` bash
ssh <bastion ip> -N -L9002:localhost:9001
```

And finally open your web browser at http://localhost:9002/t/openstack/status

### How to pause nodepool?

To pause nodepool's execution scale the deployment to 0 replicas.

``` bash
NODEPOOL_DEPLOYMENT="$(kubectl get deployments -n zuul | grep nodepool-launcher | awk '{print $1}')"
kubectl scale --replicas=0 -n zuul deployment/$NODEPOOL_DEPLOYMENT
```

To resume nodepool scale the deployment back to 1 replica.

``` bash
NODEPOOL_DEPLOYMENT="$(kubectl get deployments -n zuul | grep nodepool-launcher | awk '{print $1}')"
kubectl scale --replicas=1 -n zuul deployment/$NODEPOOL_DEPLOYMENT
```

### Reload zosci-config configuration

When reconfiguring zosci (zuul) the config-projects get updated and all the
configuration declared is loaded, this process takes around 10 minutes.

``` bash
kubectl exec --stdin --tty \
    -n zuul zuul-scheduler-0 \
    -- /usr/local/bin/python /usr/local/bin/zuul-scheduler full-reconfigure
```

Reference: https://zuul-ci.org/docs/zuul/latest/operation.html#reconfiguration
