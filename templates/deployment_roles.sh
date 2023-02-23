# Prerequisites:
# - Set up .aws/credentials profiles for DevOps, dev
# - Set TOOLS_ACCOUNT_ID, DEV_ACCOUNT_ID env variables
# - Install and configure git

# if prerequisite account values aren't set, exit
if [[ -z "${TOOLS_ACCOUNT_ID}" || -z "${DEV_ACCOUNT_ID}" ]]; then
  printf "Please set TOOLS_ACCOUNT_ID, DEV_ACCOUNT_ID"
  printf "TOOLS_ACCOUNT_ID =" ${TOOLS_ACCOUNT_ID}
  printf "DEV_ACCOUNT_ID =" ${DEV_ACCOUNT_ID}
  exit
fi

# Deploy roles without policies so the ARNs exist when the CDK Stack is deployed
printf "\nDeploying roles to UAT and Prod\n"
aws cloudformation deploy --template-file templates/CodePipelineCrossAccountRole.yml \
    --stack-name CodePipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile env_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile env_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Dev &

<<comment
# Deploy Repository CDK Stack
printf "\nDeploying Repository Stack\n"
npm install
npm audit &
npm run build
cdk synth
cdk deploy RepositoryStack --profile env_DevOps

# Deploy Pipeline CDK stack, write output to a file to gather key arn
printf "\nDeploying Cross-Account Deployment Pipeline Stack\n"

CDK_OUTPUT_FILE='.cdk_output'
rm -rf ${CDK_OUTPUT_FILE} .cfn_outputs
npx cdk deploy CrossAccountPipelineStack \
  --context uat-account=${DEV_ACCOUNT_ID}
  --profile env_DevOps \
  --require-approval never \
  2>&1 | tee -a ${CDK_OUTPUT_FILE}
sed -n -e '/Outputs:/,/^$/ p' ${CDK_OUTPUT_FILE} > .cfn_outputs
KEY_ARN=$(aws -F " " 'KeyArn/ { print $3 }' .cfn_outputs )

# Check the KEY_ARN is set after the CDK deployment
if [[ -z "${KEY_ARN}" ]]; then
  printf "\nSomething went wrong - we didn't get a Key ARN as an output from the CDK Pipeline deployment"
  exit
fi

# Update the Cloudformation roles with the Key ARN
print "\nUpdating roles with policies in UAT and Prod\n"
aws cloudformation deploy --template-file templates/CodepipelineCrossAccountRole.yml \
    --stack-name CodepipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile env_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile env_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Dev &

# Clean up temporary file
rm ${CDK_OUTPUT_FILE} .cfn_outputs
comment>>