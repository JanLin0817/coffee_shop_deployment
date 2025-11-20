#!/bin/bash

echo "Fetching AWS resources..."
export IMAGE_NAME="473837935280.dkr.ecr.us-east-1.amazonaws.com/coffee-shop/employee"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier supplierdb \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
export FAMILY="employee-microservice"

echo "✅ ACCOUNT_ID: ${ACCOUNT_ID}"
echo "✅ IMAGE_NAME: ${IMAGE_NAME}"
echo "✅ RDS_ENDPOINT: ${RDS_ENDPOINT}"
if [ -z "$ACCOUNT_ID" ] || [ -z "$IMAGE_NAME" ] || [ -z "$RDS_ENDPOINT" ] ; then
    echo "❌ missing required AWS resource information. Exiting."
    exit 1
fi


echo "copying task definition template and replacing placeholders..."
cp /home/ec2-user/environment/deployment/taskdef-employee.json /tmp/taskdef-employee-temp.json

# placeholder
sed -i "s|<IMAGE1_NAME>|${IMAGE_NAME}|g" /tmp/taskdef-employee-temp.json
sed -i "s|<RDS-ENDPOINT>|${RDS_ENDPOINT}|g" /tmp/taskdef-employee-temp.json
sed -i "s|<ACCOUNT-ID>|${ACCOUNT_ID}|g" /tmp/taskdef-employee-temp.json
sed -i "s|<ECS-FAMILY>|${FAMILY}|g" /tmp/taskdef-employee-temp.json

cat /tmp/taskdef-employee-temp.json
echo "aws ecs register-task-definition --cli-input-json file:///tmp/taskdef-employee-temp.json"
aws ecs register-task-definition --cli-input-json file:///tmp/taskdef-employee-temp.json
rm /tmp/taskdef-employee-temp.json