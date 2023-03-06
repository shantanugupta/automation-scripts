#!/bin/bash
instance="${1:-new-servername-snapshot}"
snapshot="${2:-host-servername}"
profile="${3:-prod-long-term-mfa}"

newsnapshot="${snapshot}-$(date +"%Y%m%dT%H%M")"
output="${4:-json}"
outputFileName="./output/snapshot-logs/${instance}-$(date +"%Y%m%dT%H%M").out "
echo $newsnapshot
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1> >(while read line; do echo "$(date '+%FT%T') $line" >> "$outputFileName"; done;) 2>&1
# Everything below will go to the file '$1.out':

# Defined global options that will be passed in all aws rds commands
#outputFields="jq '.DBInstances[0]|{DBInstanceIdentifier:.DBInstanceIdentifier, MultiAZ: .MultiAZ, DBInstanceStatus:.DBInstanceStatus, AvailabilityZone:.AvailabilityZone}'"
#outputFields="jq '.DBInstances[0]'"
cmdOptions="--db-instance-identifier $instance --profile $profile --output $output --no-cli-pager"

restoreOptions="--db-snapshot-identifier $snapshot  \
    --db-instance-class db.m4.large \
    --availability-zone ap-southeast-1a \
    --no-multi-az \
    --no-publicly-accessible \
    --no-auto-minor-version-upgrade \
    --engine postgres \
    --no-deletion-protection"

modifyOptions95="--apply-immediately \
    --allow-major-version-upgrade \
    --auto-minor-version-upgrade \
    --copy-tags-to-snapshot \
    --engine-version 9.5.22"

modifyOptions12="--db-instance-class db.m4.large \
    --no-deletion-protection \
    --apply-immediately \
    --allow-major-version-upgrade \
    --auto-minor-version-upgrade \
    --copy-tags-to-snapshot \
    --engine-version 12.3"

#RDS availability check and report function to report current status of RDS instance
WaitUntilRDSIsAvailable(){
    isAvailable="";    
    delay=120; #in seconds
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

postMessage(){
    webhook= "<webhook of teams>"; #"https://teamschannel.webhook.office.com/webhookb2/";
    msg="'{\"text\": \"$1\"}'"
    command=$(echo "curl -H 'Content-Type: application/json' -d $msg $webhook;")
    echo $command;
    details=$(eval $command)
}

echo "-----Restore : $instance"
command=$(echo "aws rds restore-db-instance-from-db-snapshot $cmdOptions $restoreOptions ")
details=$(eval $command)
echo $details | jq '.'

WaitUntilRDSIsAvailable    
echo "-----Upgrade instance to 9.5: $instance"
command=$(echo "aws rds modify-db-instance $cmdOptions $modifyOptions95")
details=$(eval $command)
echo $details | jq '.'

WaitUntilRDSIsAvailable
echo "-----Upgrade instance to 12.3: $instance"
command=$(echo "aws rds modify-db-instance $cmdOptions $modifyOptions12")
details=$(eval $command)
echo $details | jq '.'

WaitUntilRDSIsAvailable
echo "-----Snapshot creation: $instance"
snapshotCreationOptions="--no-skip-final-snapshot --final-db-snapshot-identifier $newsnapshot --delete-automated-backups"
command=$(echo "aws rds delete-db-instance $cmdOptions $snapshotCreationOptions")
details=$(eval $command)
echo $details | jq '.'

#postMessage "Snapshot creation completed for $instance"
