#!/bin/bash

echo "Fetching AWS resources..."
REVISION=$(aws ecs describe-task-definition \
    --task-definition customer-microservice \
    --query 'taskDefinition.revision' \
    --output text)
TG_ARN=$(aws elbv2 describe-target-groups \
    --names customer-tg-two \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
SUBNET1=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=Public Subnet1" \
    --query 'Subnets[0].SubnetId' \
    --output text)
SUBNET2=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=Public Subnet2" \
    --query 'Subnets[0].SubnetId' \
    --output text)
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=microservices-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# check if any variable is empty
echo "✅ Task Definition Version: ${REVISION}"
echo "✅ Target Group ARN: ${TG_ARN}"
echo "✅ Subnet1: ${SUBNET1}"
echo "✅ Subnet2: ${SUBNET2}"
echo "✅ Security Group: ${SG_ID}"
if [ -z "$REVISION" ] || [ -z "$TG_ARN" ] || [ -z "$SUBNET1" ] || [ -z "$SUBNET2" ] || [ -z "$SG_ID" ]; then
    echo "❌ missing required AWS resource information. Exiting."
    exit 1
fi

# Generate temp JSON file
echo "Create Task Defintio Version"
TEMP_JSON=$(mktemp)
cat > ${TEMP_JSON} <<EOF
{
    "serviceName": "customer-service",
    "taskDefinition": "customer-microservice:${REVISION}",
    "cluster": "microservices-serverlesscluster",
    "loadBalancers": [
        {
            "targetGroupArn": "${TG_ARN}",
            "containerName": "customer",
            "containerPort": 8080
        }
    ],
    "desiredCount": 1,
    "launchType": "FARGATE",
    "schedulingStrategy": "REPLICA",
    "deploymentController": {
        "type": "CODE_DEPLOY"
    },
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": ["${SUBNET1}", "${SUBNET2}"],
            "securityGroups": ["${SG_ID}"],
            "assignPublicIp": "ENABLED"
        }
    }
}
EOF

# Verify JSON format
if ! jq empty ${TEMP_JSON} 2>/dev/null; then
    echo "❌ Generated JSON Format Error:"
    cat ${TEMP_JSON}
    rm ${TEMP_JSON}
    exit 1
fi

# Display generated JSON
echo "📄 Generated JSON:"
cat ${TEMP_JSON}
echo "==========================="

# Create and verify ECS Service creation
aws ecs create-service --cli-input-json file://${TEMP_JSON}

if [ $? -eq 0 ]; then
    echo "✅ ECS Service Created！"
    rm ${TEMP_JSON}
else
    echo "❌ ECS Service Fail"
    echo "JSON File at: ${TEMP_JSON}"
    exit 1
fi
