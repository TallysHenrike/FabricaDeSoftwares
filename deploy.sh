#!/bin/bash

set -eo pipefail

############################ VARIABLES ############################
# ssh key's location                                              #
ssh_key="/home/circleci/arscrift/arscrift.pem"                    #                                                     #
############################ VARIABLES ############################

echo -e "
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                         @
@                     CONFIGURING AWS                     @
@                                                         @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"

# CONFIGURE AWS_CLI
aws --version
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region us-east-1
aws configure set default.output json

echo -e "
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                         @
@                DEPLOYING SERVICES TO AWS                @
@                                                         @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"

export _sshconfig=$(mktemp -u)
export _ssh_ctrl_socket=$(mktemp -u)

cfn_stack_name=arscrift

jqScript=".AutoScalingGroups[] | select(.Tags[].Value == \"${cfn_stack_name}-Manager\").Instances[] | select(.HealthStatus == \"Healthy\").InstanceId"
manager_id=$(aws autoscaling describe-auto-scaling-groups | jq -r "${jqScript}" | head -n1)
manager=$(aws ec2 describe-instances --instance-ids ${manager_id} | jq -r '.Reservations[].Instances[].PublicDnsName')

cat <<EOF > ${_sshconfig}
User docker
LogLevel error
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
IdentityFile ${ssh_key}
ControlPath ${_ssh_ctrl_socket}
EOF

chmod 400 ${ssh_key}

echo $manager

# Set up an SSH control socket for tunneling, so that we can cleanly close it when we're done
ssh -M -F ${_sshconfig} -fnNT -L localhost:2374:/var/run/docker.sock ${manager}

# configure all `docker` commands to communicate through the SSH tunnel instead of any local docker engine
export DOCKER_HOST=localhost:2374

# now run `docker` commands as normal:
docker stack deploy -c /home/circleci/arscrift/docker-compose.yml arscrift

# Close the tunnel
ssh -F ${_sshconfig} -O exit -
# remove the temporary SSH-related files
rm -f ${_ssh_ctrl_socket}

unset DOCKER_HOST