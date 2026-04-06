## Deployment

### 1. Get the VPC ID
```bash
aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=sg-vpc" \
    --query "Vpcs[0].VpcId" \
    --region us-east-2 \
    --output text
```

### 2. Get the Subnet ID

Replace `<VPC_ID>` with the value from the previous step:
```bash
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=<VPC_ID>" \
    --query "Subnets[0].SubnetId" \
    --region us-east-2 \
    --output text
```

### 3. Deploy the Stack

Replace `<VPC_ID>` and `<SUBNET_ID>` with the values from the steps above:
```bash
aws cloudformation create-stack \
    --stack-name SGExample \
    --template-body file://template.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-2 \
    --parameters \
        ParameterKey=VPCID,ParameterValue=<VPC_ID> \
        ParameterKey=SubnetId,ParameterValue=<SUBNET_ID>
```

### 4. Wait for Completion
```bash
aws cloudformation wait stack-create-complete \
    --stack-name SGExample \
    --region us-east-2
```

### 5. Get the Public IP
```bash
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=MyEC2Instance" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --region us-east-2 \
    --output text
```

Then open `http://<PUBLIC_IP>` in your browser to verify Apache is running.

### 6. Connect via SSM Session Manager (no SSH needed)
```bash
# Get the Instance ID first
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=MyEC2Instance" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --region us-east-2 \
    --output text

# Start a session
aws ssm start-session \
    --target <INSTANCE_ID> \
    --region us-east-2
```

## Parameters

| Parameter      | Default                   | Description                              |
|----------------|---------------------------|------------------------------------------|
| `VPCID`        | *(required)*              | VPC where the EC2 instance is launched   |
| `SubnetId`     | *(required)*              | Subnet where the EC2 instance is placed  |
| `ImageId`      | `ami-02f986bab3de34d0d`   | AMI ID for the EC2 instance              |
| `InstanceName` | `MyEC2Instance`           | Name tag applied to the EC2 instance     |

## Resources Created

| Resource             | Type                        | Description                                      |
|----------------------|-----------------------------|--------------------------------------------------|
| `SSMRole`            | `AWS::IAM::Role`            | Grants EC2 permission to use SSM Session Manager |
| `SSMInstanceProfile` | `AWS::IAM::InstanceProfile` | Attaches the IAM role to the EC2 instance        |
| `MyEC2Instance`      | `AWS::EC2::Instance`        | t3.micro running Apache via UserData             |
| `SecurityGroups`     | `AWS::EC2::SecurityGroup`   | Allows all inbound and outbound traffic          |

## Security Note

> ⚠️ The security group in this template allows **all inbound and outbound traffic**
> (`0.0.0.0/0`). This is intentional for this exercise to keep the focus on the
> CloudFormation structure. For production use, restrict ingress to specific ports
> and trusted IP ranges only. Example rules for a web server:
>
> | Port | Protocol | Source    | Purpose       |
> |------|----------|-----------|---------------|
> | 80   | TCP      | 0.0.0.0/0 | HTTP traffic  |
> | 443  | TCP      | 0.0.0.0/0 | HTTPS traffic |

## Cleanup
```bash
aws cloudformation delete-stack \
    --stack-name SGExample \
    --region us-east-2

aws cloudformation wait stack-delete-complete \
    --stack-name SGExample \
    --region us-east-2
```