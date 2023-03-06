#!/bin/bash
instance="${1:-read-replica-testing-shangupta-rr}"
profile="${2:-dev-long-term-mfa}"
output="${3:-json}"
severity=$4
outputFileName="./output/az1c/${instance}__$(date +"%Y%m%dT%H%M").out "

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1> >(while read line; do echo "$(date '+%FT%T') $line" >> "$outputFileName"; done;) 2>&1
# Everything below will go to the file '$1.out':

# Defined global options that will be passed in all aws rds commands
#outputFields="jq '.DBInstances[0]|{DBInstanceIdentifier:.DBInstanceIdentifier, MultiAZ: .MultiAZ, DBInstanceStatus:.DBInstanceStatus, AvailabilityZone:.AvailabilityZone}'"
outputFields="jq '.DBInstances[0]'"
cmdOptions="--db-instance-identifier $instance --profile $profile --output $output --no-cli-pager"

#RDS availability check and report function to report current status of RDS instance
WaitUntilRDSIsAvailable(){
    isAvailable="";    
    delay=30; #in seconds
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

#echo "--------Starting for $instance--------"
#WaitUntilRDSIsAvailable

echo "-----Print current status of RDS instance before starting: $instance"
command=$(echo "aws rds describe-db-instances $cmdOptions | $outputFields")
details=$(eval $command)
echo $details | jq '.'

#capture parameters for current RDS state
read DBInstanceIdentifier MultiAZ DBInstanceStatus AvailabilityZone DBInstanceArn < <(echo $(echo $details | jq -r '.DBInstanceIdentifier,.MultiAZ,.DBInstanceStatus,.AvailabilityZone,.DBInstanceArn'))
echo "DBInstanceIdentifier:$DBInstanceIdentifier, MultiAZ:$MultiAZ, DBInstanceStatus: $DBInstanceStatus, AvailabilityZone:$AvailabilityZone, DBInstanceArn: $DBInstanceArn"

# #add severity tag to the resources
# if [[ $severity == P* ]]; then
#     command=$(echo "aws rds add-tags-to-resource --resource-name $DBInstanceArn --tags Key=Severity,Value=$severity --profile $profile --output $output --no-cli-pager")
#     eval $command
#     echo '-----Added severity tag to instance'
# fi

#check if zone is not 1b
if [[ $AvailabilityZone != "ap-southeast-1a" ]]; then
    #Enable MultiAZ 
    if [[ $MultiAZ == "false" ]]; then
        echo "-----Enable Multi-AZ for $instance"
        command=$(echo "aws rds modify-db-instance --multi-az --apply-immediately $cmdOptions ")
        echo $command
        details=$(eval $command)
        echo $details | jq '.'
    fi

    #Reboot RDS with Failover
    # WaitUntilRDSIsAvailable
    # echo "-----Manual reboot with forced failover for $instance"
    # command=$(echo "aws rds reboot-db-instance --force-failover $cmdOptions " )
    # echo $command
    # details=$(eval $command)
    # echo $details | jq '.'

    
    #Disable Multi-AZ
    WaitUntilRDSIsAvailable
    echo "-----Disable Multi-AZ for $instance"
    command=$(echo "aws rds modify-db-instance --no-multi-az --apply-immediately $cmdOptions")
    echo $command
    details=$(eval $command)
    echo $details | jq '.'

    #Print current status 
    WaitUntilRDSIsAvailable
    echo "-----Print current status of RDS instance before ending: $instance"
    command=$(echo "aws rds describe-db-instances $cmdOptions | $outputFields")
    echo $command
    details=$(eval $command)
    echo $details | jq '.'

    echo "--------Script ended for $instance--------"
else
    echo "$instance is already in $AvailabilityZone. Skipping processing for this instance."
    if [[ $MultiAZ == "true" ]]; then
        #Disable Multi-AZ
        WaitUntilRDSIsAvailable
        echo "-----Disable Multi-AZ for $instance"
        command=$(echo "aws rds modify-db-instance --no-multi-az --apply-immediately $cmdOptions")
        echo $command
        details=$(eval $command)
        echo $details | jq '.'
    fi
fi