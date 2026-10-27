 # IaC with Terraform: Foundational AWS Infrastructure

Terraform configuration that provisions a minimal, internet-facing AWS environment (a VPC, a public subnet, an Internet Gateway with routing, a security group, and an EC2 instance running nginx) with state stored remotely in Amazon S3 and locked with DynamoDB.

**Author:** Kabera Clapton
---

## Architecture

![AWS Architectural Diagram](screenshots/architecture.png)

Traffic from the internet reaches the instance through the Internet Gateway. The subnet is public because its associated route table sends `0.0.0.0/0` to that gateway, and instances launched in it receive a public IPv4 address. The security group then decides which of that traffic is allowed in.

---

## What gets deployed

| Resource | Terraform type | Purpose |
| --- | --- | --- |
| VPC | `aws_vpc` | Isolated network, `10.0.0.0/16`, DNS hostnames enabled |
| Public subnet | `aws_subnet` | `10.0.1.0/24`, auto-assigns public IPs |
| Internet Gateway | `aws_internet_gateway` | Connects the VPC to the internet |
| Route table + association | `aws_route_table`, `aws_route_table_association` | Default route to the IGW, attached to the public subnet |
| Security group + rules | `aws_security_group`, `aws_vpc_security_group_ingress_rule`, `aws_vpc_security_group_egress_rule` | SSH from my IP only, HTTP from anywhere, all outbound |
| Key pair | `aws_key_pair` | Public key for SSH access |
| EC2 instance | `aws_instance` | t2.micro running Ubuntu 22.04, nginx installed via `user_data` |
| AMI lookup | `data.aws_ami` | Latest Canonical Ubuntu 22.04 image for the region |
| Public IP lookup | `data.http` | Detects the operator's public IP at plan time |

Not managed by this configuration: the S3 state bucket and DynamoDB lock table (see [Remote backend](#remote-backend)).

---

## Repository structure

```
.
├── README.md
├── dynamo_s3_setup.sh          # Create the DynamoDB and S3 instances to be used by in the remote backend
├── clean_up.sh                 # automates the deletion of S3 bucket and dynamo DB created for remote backend
├── main.tf                     # Network, security group, and EC2 resources
├── variables.tf                # Input variables
├── outputs.tf                  # Outputs (public IP, and SSH command)
├── .terraform.lock.hcl         # Provider dependency lock file (committed)
├── .gitignore
└── screenshots/                # Lifecycle and console evidence
```

Ignored by Git: `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `terraform.tfvars`, `tfplan`, and `crash.log`.

---

## Prerequisites

- Terraform **v1.5 or later**
- AWS CLI v2 configured with an IAM identity (not the root user)
- An SSH key pair on the local machine
- The S3 bucket and DynamoDB table described below, created before running `terraform init`

Verify the setup:

```bash
terraform -version
aws sts get-caller-identity
```

---

## Remote backend

State is stored in S3 and locked with DynamoDB. Both resources are created using the script `dynamo_s3_setup.sh` and are deliberately outside Terraform's control (see [Design decision 1](#1-backend-resources-created-manually)).

### Required IAM permissions

The identity running Terraform needs, at minimum:

- `s3:ListBucket` on the bucket
- `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on the state key
- `dynamodb:GetItem`, `dynamodb:PutItem`, and `dynamodb:DeleteItem` on the lock table

### To recreate the backend in another account

1. Create an S3 bucket in `eu-west-1` with a globally unique name. Enable versioning; leave Block Public Access and default encryption on.
2. Create a DynamoDB table with partition key `LockID` of type String and on-demand capacity.
3. Update the values in `main.tf` and run `terraform init`.

---

## Usage

```bash
# 1. Clone and enter the repository
git clone <repo-url>
cd <repo-name>

# 2. Initialise: downloads the providers and connects to the S3 backend
terraform init

# 3. Check formatting and validity
terraform fmt -check
terraform validate

# 4. Create a plan and review it
terraform plan -out=tfplan

# 5. Apply exactly the reviewed plan
terraform apply tfplan

# 6. Verify
terraform output
<public ip for EC2 instance>
ssh -i ~/.ssh/<private-key> ubuntu@$(terraform output -raw public_ip)

# 7. Tear down
terraform destroy
```

Saving the plan with `-out` and applying that file guarantees that what gets applied is exactly what was reviewed, even if the code or infrastructure changes in between.

### Inputs

| Variable | Description | Default |
| --- | --- | --- |
| `region` | AWS region to deploy into | `eu-west-1` |
| `vpc_cidr` | CIDR block for the VPC | `10.0.0.0/16` |
| `pub_cidr` | CIDR block for the public subnet | `10.0.1.0/24` |
| `instance_type` | EC2 instance type | `t2.micro` |

### Outputs

| Output | Description |
| --- | --- |
| `public_ip` | Public IPv4 address of the EC2 instance |
| `ssh_string` | The ssh command to access the EC2 instance |

---

## Design decisions

### 1. Backend resources created manually

The S3 bucket and DynamoDB table were created by a shell script rather than with Terraform.

**Why:** a configuration cannot store its state in a bucket it creates itself. On the first `terraform init`, the bucket does not exist yet, and `terraform destroy` would try to delete the very bucket that holds the state of the running destroy. Keeping the backend outside Terraform means no `terraform destroy` in this repository can ever affect the state store.

**Trade-off:** these two resources are not managed by terraform and thus do not provide the benefits of terraform managed resources.

### 2. DynamoDB locking vs. `use_lockfile`

The lab requires a DynamoDB lock table, so this configuration uses `dynamodb_table`.

When a Terraform operation starts, it writes an item with key `LockID` to the table using a conditional write. If another operation already holds the lock, the conditional write fails and the second run waits or exits with a lock error. The item is deleted when the operation finishes. If a crash leaves a stale lock, it can be cleared with `terraform force-unlock <LOCK_ID>`, which should only be done after confirming nothing else is running.

**However, DynamoDB-based locking is now deprecated.** Since Terraform 1.11, the S3 backend supports native locking: with `use_lockfile = true`, Terraform creates a `.tflock` object next to the state file using S3 conditional writes, and no DynamoDB table is needed. The `dynamodb_table` argument is deprecated and scheduled for removal in a future version.

The modern equivalent of this backend is:

```hcl
terraform {
  backend "s3" {
    bucket       = "sandbox-remote-backend723354237"
    key          = "sandbox/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

This removes a whole AWS resource, its IAM permissions, and its cost. Adopting it requires raising `required_version` to `>= 1.11`. During a migration, both `dynamodb_table` and `use_lockfile` can be set at the same time, so locks are held in both places until DynamoDB can be removed.

### 3. Public IP detected automatically with the `http` data source

SSH must be allowed only from the operator's IP. Rather than hardcoding an address, the configuration looks it up each time it runs:

```hcl
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}
```

`chomp()` strips the trailing newline from the response, and `/32` restricts the rule to that single address.

**Why:** home and mobile connections usually get dynamic public IPs, which change after a router restart or when switching networks. With a hardcoded value, SSH would silently stop working and the variable would need manual updates. With the lookup, running `terraform apply` again updates just the SSH rule in place.

---

## Evidence

### Tooling

**`terraform init`** connecting to the S3 backend:

![terraform init](screenshots/t-init.png)

**`terraform plan`:**

![terraform plan](screenshots/t-plan.png)

**`terraform apply`:**

![terraform apply](screenshots/t-apply.png)

**`terraform destroy`:**

![terraform destroy](screenshots/t-destroy.png)

**State List** (list the resources being managed by the terraform state):

![State List](screenshots/t-state-list.png)

---

## Cleanup

`terraform destroy` removes everything this configuration created. The backend resources are intentionally left in place. To remove them when they are no longer needed:

`./clean_up.sh` uses the **aws cli** to delete the S3 bucket and the DynamoDB table.

---

## Possible improvements

- Migrate locking to `use_lockfile` and retire the DynamoDB table.
- Replace SSH access with AWS Systems Manager Session Manager, so no inbound port 22 is needed and access is controlled by IAM.
