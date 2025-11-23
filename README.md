
## ECS

### Task Definition
We need to set the all the placeholder in taskdef-xxx.json
Follow register-taskdef-xxx.sh
- `aws ecs register-task-definition --cli-input-json "file:///home/ec2-user/environment/deployment/taskdef-customer.json"`


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

## Code Pipline

update taskdef-xxx to taskdef-pipline-xxx for codepipline
- TODO: parmameterize `account-id` and `RDS-ENDPOINT`


## TODO
task def and create service use 2 different script tech