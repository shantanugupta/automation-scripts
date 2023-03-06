#!/bin/bash
instance="${1:-read-replica-testing-shangupta}"
profile="${2:-dev-long-term-mfa}"
engineVersion="${3:-engineVersion}"
severity=$4
output="${5:-json}"
today=$(date +"%Y-%m-%d")
mkdir -p $today

outputFileName="./output/rds-uprade/$today/${instance}__$(date +"%Y%m%dT%H%M").out "

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1> >(while read line; do echo "$(date '+%FT%T') $line" >> "$outputFileName"; done;) 2>&1
# Everything below will go to the file '$1.out':

# Defined global options that will be passed in all aws rds commands
outputFields="jq '.DBInstances[0]'"
cmdOptions="--db-instance-identifier $instance --profile $profile --output $output --no-cli-pager"

#RDS availability check and report function to report current status of RDS instance
WaitUntilRDSIsAvailable(){
    isAvailable="";    
    delay=60; #in seconds
    waitCount=0; 
    waitFor=36000 #wait for 10 hours before terminating
    #aws rds wait db-instance-available --db-instance-identifier $instance --profile $profile --output $output --no-cli-pager # this statement not working in bash script mode
    echo "--Wait until $instance current status is available"
    while [[ $isAvailable != "available" && $waitCount -lt $waitFor ]];do
        sleep $delay
        ((waitCount+=$delay))

        isAvailable=$(aws rds describe-db-instances --query DBInstances[*].DBInstanceStatus --db-instance-identifier $instance --profile $profile --output text --no-cli-pager)
        echo "----Current status: $isAvailable, waiting since $waitCount seconds, timeout after $(($waitFor/60)) minutes"
    done
}

echo "--------Updating Severity tag for $instance--------"

echo "-----Print current status of RDS instance before starting: $instance"
command=$(echo "aws rds describe-db-instances $cmdOptions | $outputFields")
details=$(eval $command)
echo $details | jq '.'

#capture parameters for current RDS state
read DBInstanceArn < <(echo $(echo $details | jq -r '.DBInstanceArn'))
echo "DBInstanceArn: $DBInstanceArn"


#add severity tag to the resources
if [[ $severity == P* ]]; then
    command=$(echo "aws rds add-tags-to-resource \
    --resource-name $DBInstanceArn \
    --tags Key=Severity,Value=$severity \
    --profile $profile \
    --output $output \
    --no-cli-pager")
    echo $command
    eval $command
    echo "-----Added severity($severity) tag to instance($instance)"
fi

echo "-----Upgrade RDS instance before starting: $instance"
command=$(echo "aws rds modify-db-instance $cmdOptions \
--engine-version $engineVersion
--no-allow-major-version-upgrade \
--no-auto-minor-version-upgrade \
--apply-immediately")

echo $command
eval $command

WaitUntilRDSIsAvailable