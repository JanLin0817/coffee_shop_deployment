
## Table of Contents

- [Introduction](#introdduction)
- [ECR](#ecr)
  - [Create Repo](#create-repo)
  - [Push](#push)
- [ECS](#ecs)
  - [Create Cluster](#create-cluster)
  - [Task Definition](#task-definition)
  - [Create Service](#create-service)
- [ELB](#elb)
  - [Target Group](#target-group)
  - [Application Load Balancer](#application-load-balancer)
- [CodeDeploy](#codedeploy)
  - [AppSpec](#appspec)
  - [Task Definition](#task-definition-1)
- [Code Pipeline](#code-pipline)
- [TODO](#todo)

## Introdduction
In this project
- We have two service `customer` and `employee` pushing to ECR. 
- Combine codepipline and codedeploy creating ECS
- Expose ECS through Fargate on load balancer

Detail, walk through
- ECR -> ECS -> ELB
- add-on code pipline and codedeploy

## ECR

### Create Repo
1. Create Repo: `customer`, `employee`
2. Set ECR repo permissions | [Doc](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)
```JSON
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "ecr:*"
    }
   ]
}
```
> TODO: Principle of Least Privilege

### Push
1. Tag Image
```bash
account_id=$(aws sts get-caller-identity |grep Account|cut -d '"' -f4)

# Verify that the account_id value is assigned to the $account_id variable
echo $account_id

# Tag both image
docker tag customer:latest $account_id.dkr.ecr.us-east-1.amazonaws.com/customer:latest
docker tag employee:latest $account_id.dkr.ecr.us-east-1.amazonaws.com/employee:latest

docker image ls
```

2. Authorize Docker client connecting to the Amazon ECR service -> `Login Succeeded`
```bash
account_id=$(aws sts get-caller-identity |grep Account|cut -d '"' -f4)
echo $account_id
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $account_id.dkr.ecr.us-east-1.amazonaws.com
```

3. Push and check images are stored in ECR
```bash
docker push $account_id.dkr.ecr.us-east-1.amazonaws.com/<REPO-NAME>:latest
```
---

## ECS

### Create Cluster
In 2025 version, cluster only need **Name** and **Select a method of obtaining compute capacity**
- name: `microservices-serverlesscluster`
-  method of obtaining compute capacity: `Fargate only`

> TODO: doc link
---

### Task Definition
[Amazon ECS task definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
#### 1. Create taskdef-xxx.json file as template
#### 2. In register-taskdef-xxx.sh script
- Set all the placeholder in taskdef-xxx.json 
- `aws ecs register-task-definition --cli-input-json "file:///home/ec2-user/environment/deployment/taskdef-customer.json"`

task-def show on [Task definitions pane](https://us-east-1.console.aws.amazon.com/ecs/v2/task-definitions?region=us-east-1)

### Create Service
After adding this config, service can only update by codedeploy.
Without this after `schedulingStrategy` config, services can update by ECS.
```
    "deploymentController": {
        "type": "CODE_DEPLOY"
    },
```
Follow create-xxx-service.sh
- `aws ecs create-service --cli-input-json file://${TEMP_JSON}`

## ELB
Create TG -> Add to LB
### Target Group

Create Target Group for `employee` and `customer` services
- In this task, we create 2 extra indentical TG for blue/green deployment.
- CodeDeploy requires two target groups for each deployment group

General Setting
- **Target type**: IP addresses  
- **Protocol**: HTTP  
- **Port**: `8080`  
- **VPC**: `LabVPC`  
- **Register targets**: define it later
---

Customize Setting for each TG

| Microservice | Target Group Name | Health Check Path |
|-------------|------------------|-------------------|
| Customer    | `customer-tg-one` | `/` |
| Customer    | `customer-tg-two` | `/` |
| Employee    | `employee-tg-one` | `/admin/suppliers` |
| Employee    | `employee-tg-two` | `/admin/suppliers` |
---

> Note: Blue/green is a deployment strategy where you create two separate but identical environments. One environment (blue) runs the current application version, and one environment (green) runs the new application version. For more information, see [Blue/Green](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html) Deployments in the Overview of Deployment Options on AWS whitepaper.

### Application Load Balancer

# ✅ Create Application Load Balancer for Microservices

1️⃣ Create Security Group
- **Name**: `microservices-sg`  
- **VPC**: `LabVPC`  
- **Inbound Rules**

    | Type  | Protocol | Port | Source  |
    |------|---------|------|--------|
    | HTTP | TCP     | 80   | 0.0.0.0/0 |
    | HTTP | TCP     | 8080 | 0.0.0.0/0 |

---

2️⃣ Create Application Load Balancer
| Setting | Value |
|------|------|
| Name | `microservicesLB` |
| Scheme | Internet-facing |
| IP address type | IPv4 |
| VPC | `LabVPC` |
| Subnets | `Public Subnet1`, `Public Subnet2` |
| Security Group | `microservices-sg` |
---

3️⃣ Listener
| Listener | Protocol | Port | Default Target Group |
|---------|----------|-----|-------------------|
| Listener 1 | HTTP | `80` | `customer-tg-two` |
| Listener 1 | HTTP | `80` | `employee-tg-two` |
| Listener 2 | HTTP | `8080` | `customer-tg-one` |
| Listener 2 | HTTP | `8080` | `employee-tg-one` |
---

4️⃣  Path-based Routing 
After createing ALB go to Load Balancers -> choice the one we created -> Listeners and rules -> Manage rules -> Add/Edit ruels
- Conditions: Path

| Path | Actions |
|----------------|-------------|
| Path = `/admin/*` | Forward to `employee-tg-two` |
| Path = `/admin/*` | Forward to `employee-tg-one` |

## Checkpoint
- Now we can access our app through ALB DNS
- ECS and ECR setting is done following is CI/CD Setting


## CodeDeploy

We need to modify **Task Definition** and **Create Service** to fit **CodeDeploy**

### AppSpec
AppSpec is a configuration file that tells AWS CodeDeploy how to deploy your application, specifying 
- the deployment target
- container details
- and load balancer settings for ECS services.

See `appspec-xxx.yaml` in the repo

### Task Definition
Update taskdef-xxx to taskdef-pipline-xxx for **CodePipeline**
- Set `"image": "<IMAGE1_NAME>",` as placefolder 

> TODO: push to CodeCommit
> TODO: CodePipeline vs CodeDeploy

### Create Service

Add this to create service .json file
- see `create-service-xxx.sh`
```
    "deploymentController": {
        "type": "CODE_DEPLOY"
    },
```


## Code Pipline


- TODO: parmameterize `account-id` and `RDS-ENDPOINT`


## TODO
task def and create service use 2 different script tech