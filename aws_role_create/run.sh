#!/bin/bash

if [ $# -eq 0 ]
then
    echo "Usage: ./run.sh <aws_saml_profile_name>"
    exit
fi

ACCOUNT_NAME=$1

ROLE_NAME="Unity-CS_Service_Role"
POLICY_LIST=(AmazonEC2ContainerRegistryPowerUser AmazonS3ReadOnlyAccess AmazonSSMManagedInstanceCore CloudWatchAgentServerPolicy DatalakeKinesisPolicy McpToolsAccessPolicy U-CS_Service_Policy U-CS_Service_Policy_Ondemand)
DYNAMIC_POLICY_LIST=(U-CS_Service_Policy U-CS_Service_Policy_Ondemand)


## Clean up existing roles and policies
## Detach the proper policies from the role
aws iam list-policies --profile ${ACCOUNT_NAME} > policies.list
## Attach the proper policies to the role
for POLICY_NAME in "${POLICY_LIST[@]}"
do
    POLICY_ARN=$(cat policies.list |jq '.Policies[]' |jq 'select(.PolicyName == "'${POLICY_NAME}'")' |jq -r '.Arn')
    aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN} --profile ${ACCOUNT_NAME}
done


## Delete dynamically created policies
for POLICY_NAME in "${DYNAMIC_POLICY_LIST[@]}"
do
    POLICY_ARN=$(cat policies.list |jq '.Policies[]' |jq 'select(.PolicyName == "'${POLICY_NAME}'")' |jq -r '.Arn')
    aws iam delete-policy --policy-arn ${POLICY_ARN} --profile ${ACCOUNT_NAME}
done


aws iam delete-role-policy --role-name ${ROLE_NAME} --policy-name U-CS_Minimum_ECS-Policy --profile ${ACCOUNT_NAME}

## Remove the instance profile
aws iam remove-role-from-instance-profile --instance-profile-name ${ROLE_NAME} --role-name ${ROLE_NAME} --profile ${ACCOUNT_NAME}
aws iam delete-instance-profile --instance-profile-name ${ROLE_NAME}-instance-profile --profile ${ACCOUNT_NAME}

## Finally, delete the role
aws iam delete-role --role-name ${ROLE_NAME} --profile ${ACCOUNT_NAME}








## Set the SSM parameters
## VPC ID
VPC_ID=$(aws ec2 describe-vpcs --vpc-ids --profile unity-cm |grep VpcId |sed 's/^.*: "//g'|sed 's/",//g')
echo "VPC_ID: $VPC_ID"
#exit

## Get the account number
aws sts get-caller-identity --profile ${ACCOUNT_NAME} > identity.txt
ACCOUNT_NUMBER=$(cat identity.txt|jq -r '.Account')
echo "Account Number: $ACCOUNT_NUMBER"

## Create the role to act as a service role
#aws iam create-role --role-name U-CS-Service-Role-Test --permission-boundary arn:aws:iam::865428270474:policy/mcp-tenantOperator-AMI-APIG --output role.out
aws iam create-role --role-name ${ROLE_NAME} --permissions-boundary arn:aws:iam::${ACCOUNT_NUMBER}:policy/mcp-tenantOperator-AMI-APIG --assume-role-policy-document file://U-CS_Service_Role_Trust_Policy.json --profile ${ACCOUNT_NAME} > role.txt
cat role.txt
ROLE_ARN=$(cat role.txt|jq -r '.Role.Arn')
echo "Role ARN: $ROLE_ARN"


## Add the inline policy
aws iam put-role-policy --role-name ${ROLE_NAME} --policy-name U-CS_Minimum_ECS-Policy --policy-document file://Minimum_ECS_Policy.json --profile ${ACCOUNT_NAME} >output.txt
cat output.txt

## U-CS Managed (These need to be created beforehand)
# U-CS_Service_Policy
aws iam create-policy --policy-name U-CS_Service_Policy --policy-document file://U-CS_Service_Policy.json --description "Policy containing permissions for automated U-CS Operations" --tags Key=ServiceArea,Value=U-CS --profile ${ACCOUNT_NAME} > output.txt
cat output.txt
# U-CS_Service_Policy_Ondemand
aws iam create-policy --policy-name U-CS_Service_Policy_Ondemand --policy-document file://U-CS_Service_Policy_Ondemand.json --description "Policy containing additional permissions for automated U-CS Operations" --tags Key=ServiceArea,Value=U-CS --profile ${ACCOUNT_NAME} > output.txt
cat output.txt

## Get the arns for the policies that we need attached
aws iam list-policies --profile ${ACCOUNT_NAME} > policies.list


## Attach the proper policies to the role
for POLICY_NAME in "${POLICY_LIST[@]}"
do
    POLICY_ARN=$(cat policies.list |jq '.Policies[]' |jq 'select(.PolicyName == "'${POLICY_NAME}'")' |jq -r '.Arn')
    echo "POLICY_ARN: $POLICY_ARN"
    aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN} --profile ${ACCOUNT_NAME}
done


## Attach 
aws iam create-instance-profile --instance-profile-name ${ROLE_NAME}-instance-profile --profile ${ACCOUNT_NAME}
aws iam add-role-to-instance-profile --instance-profile-name ${ROLE_NAME}-instance-profile --role-name ${ROLE_NAME} --profile ${ACCOUNT_NAME}
