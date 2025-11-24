
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
  - [Task Definition](#task-definition)
  - [Create Service](#create-service)
  - [Applications](#applications)
- [CodePipeline](#codepipeline)
  - [🔧 Common Configuration](#common-configuration)
  - [🔍 Differences Between Customer & Employee Pipelines](#differences-between-customer--employee-pipelines)
  - [➕ Add ECR Image Source (for both pipelines)](#add-ecr-image-source-for-both-pipelines)
  - [✏️ Edit Deploy Stage (both pipelines)](#edit-deploy-stage-both-pipelines)
- [Test the CI/CD Pipeline & Blue/Green Deployment](#test-the-cicd-pipeline--bluegreen-deployment)



## Introdduction
In this project
- We have two service `customer` and `employee` pushing to ECR. 
- Combine codepipline and codedeploy creating ECS
- Expose ECS through Fargate on load balancer

Detail, walk through
- ECR -> ECS -> ELB
- Add-on `code pipline` and `codedeploy`

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

### Applications
- Use the same Load Balancer and listener ports
- Use all-at-once traffic shifting
- Terminate the old revision after 5 minutes

1️⃣ Create CodeDeploy Application (ECS)

Use the **CodeDeploy console** to create an application with the following settings:

- **Application name:** `microservices`
- **Compute platform:** `Amazon ECS`

> ⚠️ **Important:** Do NOT create a deployment group yet in this step.
---

2️⃣ Create Deployment Groups
- `CodeDeploy > Applications > microservices > Create deployment group`

#### Common Configuration

**Deployment group name**: REFERENCE TABLE

**Service role**: `DeployRole`

**Environment configuration**: 
- cluster name: `microservices-serverlesscluster`
- ECS servuce name: REFERENCE TABLE

**Load balancers**
- **Load balancer:** `microservicesLB`
- **Production listener port:** `HTTP:80`
- **Test listener port:** `HTTP:8080`
- **Target Group Name 1:** REFERENCE TABLE
- **Target Group Name 1:** REFERENCE TABLE

**Deployment settings**
- **Traffic rerouting:** `Reroute traffic immediately`
- **Deployment configuration:** `CodeDeployDefault.ECSAllAtOnce`
- **Original revision termination:**
  - Days: `0`
  - Hours: `0`
  - Minutes: `5`

---

#### Differences between the two Deployment Groups

| Field                    | Customer Microservice         | Employee Microservice         |
|-------------------------|-------------------------------|-------------------------------|
| **Deployment group name** | `microservices-customer`      | `microservices-employee`      |
| **ECS service name**       | `customer-microservice`        | `employee-microservice`        |
| **Target group 1 name**     | `customer-tg-two`               | `employee-tg-two`               |
| **Target group 2 name**     | `customer-tg-one`               | `employee-tg-one`               |

Click **Create deployment group** after completing the configuration for each.

---
## CodePipeline
### 🔧 Common Configuration

- **Service role:** `PipelineRole`
- **Source provider**
  - Provider: `AWS CodeCommit`
  - Repository: `deployment`
  - Branch: `dev`

> Note: Skip the build stage.
- **Deploy provider**
  - Provider: `Amazon ECS (Blue/Green)`
  - Region: `US East (N. Virginia)`
  - CodeDeploy application: `microservices`
  - Deployment group: ➜ *REFERENCE TABLE*
- **Amazon ECS Task Definition (from SourceArtifact)**
  - **Input artifact:** `SourceArtifact`
  - **Task definition path:** ➜ *REFERENCE TABLE*
- **AWS CodeDeploy AppSpec file**
  - **Input artifact:** `SourceArtifact`
  - **AppSpec path:** ➜ *REFERENCE TABLE*

---

### 🔍 Differences Between Customer & Employee Pipelines

| Field | Customer Microservice | Employee Microservice |
|-------|------------------------|------------------------|
| **Pipeline name** | `update-customer-microservice` | `update-employee-microservice` |
| **Deployment group** | `microservices-customer` | `microservices-employee` |
| **Task definition file** | `taskdef-customer.json` | `taskdef-employee.json` |
| **AppSpec file** | `appspec-customer.yaml` | `appspec-employee.yaml` |
| **ECR repository name** | `customer` | `employee` |
| **Output artifact name** | `image-customer` | `image-employee` |
| **Placeholder text in taskdef** | `IMAGE1_NAME` | `IMAGE1_NAME` |

---

### ➕ Add ECR Image Source (for both pipelines)

**Action name:** `Image`  
**Provider:** `Amazon ECR`  
**Repository name:** ➜ *REFERENCE TABLE*  
**Image tag:** `latest`  
**Output artifacts:** ➜ *REFERENCE TABLE*

---

### ✏️ Edit Deploy Stage (both pipelines)

1. Add input artifact:  
   - `image-customer` **or** `image-employee`

2. Under **Dynamically update task definition image**:  
   - Input artifact with image details: `image-customer` / `image-employee`  
   - Placeholder text: `IMAGE1_NAME`

> This replaces the placeholder inside the task definition with the actual ECR image URI.

## 4️⃣ Test the CI/CD Pipeline & Blue/Green Deployment

This section describes how to test the customer or employee CI/CD pipeline and observe how CodeDeploy performs an Amazon ECS Blue/Green deployment.

---

### 1. Push a New Version → Trigger the Pipeline

When you push an update to either the **customer** or **employee** microservice into the `dev` branch of the `deployment` repository:

- CodePipeline is automatically triggered
- The pipeline runs:  
  **Source (CodeCommit) → Image (ECR) → Deploy (ECS Blue/Green)**
- CodeDeploy creates a new task set (Green) and begins the deployment process

---

### 2. Modify the Service Configuration (e.g., Desired Count)

You can manually update the ECS service through:

**Amazon ECS → Services → Edit**

Examples:
- Change the **desired count**
- Manually select a different **task definition revision**
- `aws ecs update-service --cluster microservices-serverlesscluster --service customer-service --desired-count 2`
> **Note:**  
> Updating the service manually does *not* trigger the pipeline.  
> ECS will simply launch tasks based on the task definition you select.

---

### 3. What Happens When You Modify the Task Definition?

If you update the task definition files (`taskdef-customer.json` or `taskdef-employee.json`) and push the change:

- The pipeline reads the updated task definition
- During the Deploy stage, CodePipeline automatically replaces the `IMAGE1_NAME` placeholder with the latest ECR image URI
- CodeDeplo

---

### 4. Observe Blue/Green Deployment Behavior

During deployment, you can observe activity in both the **ECS console** and the **ALB Target Groups**:

#### ✔ Target Groups Alternate During Blue/Green  
CodeDeploy switches between:

- `customer-tg-one` / `customer-tg-two`  
- `employee-tg-one` / `employee-tg-two`  

Each deployment attaches the *Green* target group and removes the *Blue* one.

#### ✔ ALB Listener Logic (8080 → 80)

Blue/Green deployment follows this sequence:

1. The Green task set is first registered with the **Test Listener (HTTP:8080)**  
2. ALB performs health checks against port **8080**  
3. After passing health checks, ALB switches the **Production Listener (HTTP:80)** to the Green target group  

This ensures:

- The new version is tested first  
- Production traffic is only routed after validation  
- Automatic rollback occurs if the test target group becomes unhealthy

---