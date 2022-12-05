# Terraform Scripts for deploying the Unreal Pixel Streaming infrastructure on OCI OKE

## Deploy Using the Terraform CLI

### Clone the Module

Clone the source code from suing the following command:

```bash
git clone github.com/oracle-quickstart/oke-unreal-pixel-streaming
```

```bash
cd oke-unreal-pixel-streaming/deploy/terraform
```

### Updating Terraform variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Update the `terraform.tfvars` file with the required variables, including the OCI credentials information.

Make sure that the information of the Instance Shape on each Node Pool are correct and you have enough quota to deploy the infrastructure, including the GPU nodes. This scripts defaults to `BM.GPU.A10.4`.

### Running Terraform

After specifying the required variables you can run the stack using the following commands:

```bash
terraform init
```

```bash
terraform plan
```

```bash
terraform apply
```

### Destroying the Stack

```bash
terraform destroy -refresh=false
```

> Note: The `-refresh=false` flag is required to prevent Terraform from attempting to refresh the state of the kubernetes API url, which will return `localhost` without the refresh-false.

### Deploying the demo app

After the infrastructure is deployed, you can deploy the demo app using the following commands:

```bash
kubectl create ns demo
```

```bash
kubectl apply -f ../demo.yaml
```

> Note: Demo App uses Prebuilt images are included with this repo, along with a demo Pixel Streaming image. You can build your own images using the instructions [here](../README.md#pixel-streaming-build).

## Questions

If you have an issue or a question, please take a look at our [FAQs](./FAQs.md) or [open an issue](https://github.com/oracle-quickstart/oke-unreal-pixel-streaming/issues/new).
