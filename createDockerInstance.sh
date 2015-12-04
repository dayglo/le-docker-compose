# This script sets up a docker machine on AWS with a static IP and DNS entry.

# To run this script, you need:-

#   on AWS:-
#     - a VPC with a public subnet
#     - a hosted zone set up that you can add a resource record to.
#     - a user with EC2 and Route53 permissions
#   on your machine:-
#     - docker-machine: https://www.docker.com/docker-toolbox
#     - aws cli: https://aws.amazon.com/cli/
#     - jq: https://stedolan.github.io/jq/

# Before running, make sure you have the following environment variables:-

#   export AWS_SECRET_ACCESS_KEY=your-secret-access-key
#   export AWS_ACCESS_KEY_ID=your-access-key-id
#   export AWS_REGION=your-region-id (I use eu-west-1) 
#   export AWS_DEFAULT_REGION=$AWS_REGION
#   export AWS_VPC_ID=your-vpc-id

set -e

subdomain=$1
domain=$2

dmName=$subdomain.$domain



# pain in the arse 'cos subnets dont seem to create instantly - leave this for terraform.
# vpcDoc=`aws ec2 create-vpc --cidr-block 10.0.0.0/16`
# vpcId=`echo $vpcDoc | node -p -e "JSON.parse(require('fs').readFileSync('/dev/stdin').toString()).Vpc.VpcId"`
# aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.1.0/24

#--------------------------------------------------------------------------------------------------------
echo Allocate elastic IP...
elasticIpDoc=`aws ec2 allocate-address`
ip=`echo $elasticIpDoc | jq -r '.PublicIp'`
allocationId=`echo $elasticIpDoc | jq -r '.AllocationId'`
sleep 3

#--------------------------------------------------------------------------------------------------------
echo Create docker machine on aws...

docker-machine create  \
  --driver amazonec2 \
  --amazonec2-region "$AWS_REGION" \
  --amazonec2-instance-type "t2.micro"  \
  --amazonec2-access-key "$AWS_ACCESS_KEY_ID" \
    --amazonec2-secret-key "$AWS_SECRET_ACCESS_KEY" \
    --amazonec2-vpc-id "$AWS_VPC_ID" \
    --amazonec2-zone c \
    $dmName

#--------------------------------------------------------------------------------------------------------
echo Checking port 80 and 443 are already open. If not, open them.
dockerMachineGroupDoc=`aws ec2 describe-security-groups | jq -r ".SecurityGroups[] | select(.GroupName==\"docker-machine\")"`
groupId=`echo $dockerMachineGroupDoc | jq -r "select(.VpcId==\"$AWS_VPC_ID\").GroupId"`
fromPort80Doc=`echo $dockerMachineGroupDoc | jq -r '.IpPermissions[] | select(.FromPort==80)'`
fromPort443Doc=`echo $dockerMachineGroupDoc | jq -r '.IpPermissions[] | select(.FromPort==443)'`

if [ "$fromPort80Doc" != "" ]; then
  echo port 80 found in docker-machine security group
else
  echo port 80 not found in docker-machine security group. Adding...
  aws ec2 authorize-security-group-ingress --group-id $groupId --protocol tcp --port 80 --cidr 0.0.0.0/0
fi

if [ "$fromPort443Doc" != "" ]; then
  echo port 443 found in docker-machine security group
else
  echo port 443 not found in docker-machine security group. Adding...
  aws ec2 authorize-security-group-ingress --group-id $groupId --protocol tcp --port 443 --cidr 0.0.0.0/0
fi

#--------------------------------------------------------------------------------------------------------
echo Adding DNS entry...
instanceId=`docker-machine inspect $dmName | jq -r '.Driver.InstanceId'`
echo aws ec2 associate-address --instance-id $instanceId --allocation-id $allocationId
aws ec2 associate-address --instance-id $instanceId --allocation-id $allocationId

#--------------------------------------------------------------------------------------------------------
echo Regenerate docker client certs...
docker-machine regenerate-certs -f $dmName
echo  Docker machine now running on $ip
eval "$(docker-machine env $dmName)"

#--------------------------------------------------------------------------------------------------------
echo Getting zone Id...
hostedZonesDoc=`aws route53 list-hosted-zones`
zoneIdString=`echo $hostedZonesDoc | jq -r ".HostedZones[] | select(.Name==\"$domain.\").Id"`
zoneId=${zoneIdString:12} 
echo Zone ID for $domain is $zoneId

#--------------------------------------------------------------------------------------------------------
echo Adding DNS entry...
dnsDoc="{\
  \"Comment\": \"Automatically created. Thx automationlogic x opsrobot!\",\
  \"Changes\": [\
    {\
      \"Action\": \"CREATE\",\
      \"ResourceRecordSet\": {\
        \"Name\": \"$subdomain.$domain.\",\
        \"Type\": \"A\",\
        \"TTL\": 300,\
        \"ResourceRecords\": [\
          {\
            \"Value\": \"$ip\"\
          }\
        ]\
      }\
    }\
  ]\
}"
dnsEntryDoc=`aws route53 change-resource-record-sets --hosted-zone-id $zoneId --change-batch "$dnsDoc"`
dnsEntryIdString=`echo $dnsEntryDoc | jq -r '.ChangeInfo.Id'`
dnsEntryId=${dnsEntryIdString:8} 
echo Dns entry Id: $dnsEntryId

#--------------------------------------------------------------------------------------------------------
echo -e "\033[36m INFO: \e[0m To connect to the newly created docker machine, you need to type: "
echo "eval \"$(docker-machine env $dmName)\""
