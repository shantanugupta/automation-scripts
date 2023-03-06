#https://www.percona.com/blog/postgresql-logical-replication-using-an-rds-snapshot/
# /*
# change in any of the below parameters require a rds reboot
# Verify the PostgreSQL parameters for logical replication
# shared_preload_libraries - pglogical
# */
# select name, setting, 
# boot_val, reset_val, pending_restart 
# from pg_settings where name in (
#         'wal_level',
#         'track_commit_timestamp',
#         'max_worker_processes',
#         'max_replication_slots',
#         'max_wal_senders') ;

# /*
#  name          | setting
# ------------------------+---------
#  max_replication_slots  | 10
#  max_wal_senders        | 10
#  max_worker_processes   | 10
#  track_commit_timestamp | on
#  wal_level              | logical
#  */
       
# --Create the replication user and grant all the required privileges     
# CREATE USER pgrepuser WITH password 'SECRET';
# GRANT rds_replication TO pgrepuser;
# GRANT SELECT ON ALL TABLES IN SCHEMA public TO pgrepuser;

# --Create a publication
# CREATE PUBLICATION pglogical_rep01 FOR ALL TABLES;

# select * from pg_replication_slots;

# --Create a replication slot
# SELECT pg_create_logical_replication_slot('pglogical_rep01', 'pgoutput');


# CLEANUP
# DROP PUBLICATION IF EXISTS pglogical_rep01;
# REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM pgrepuser;
# DROP USER pgrepuser;
# select pg_drop_replication_slot('pglogical_rep01');

#TODO: PK, UK, Identity key check

profile=dev-long-term-mfa
source_db_identifier="${1:-read-replica-testing-shangupta}"
destination_db_identifier="${2:-$source_db_identifier-13a}"
snapshot_identifier="${3:-$source_db_identifier-snapshot-13a}"
dest_param_grp_name="${5:-$destination_db_identifier-pg}"
logpath="${6:-./$destination_db_identifier.log}"

echo "-------------------PARAMETER VALUES-----------------------
AWS Profile                 : ${profile}
Source                      : ${source_db_identifier}
Destination                 : ${destination_db_identifier}
Source-snapshot             : ${snapshot_identifier}
Destination Parameter Group : ${dest_param_grp_name}
Log file name               : ${logpath}
----------------------------------------------------------------"

WaitUntilRDSIsAvailable(){
    instance=$1;
    isAvailable="";    
    delay=60;
    waitCount=0; 
    waitFor=36000 
    echo "$(date +'%F %T %Z')--Wait until $instance current status is available"
    while [[ $isAvailable != "available" && $waitCount -lt $waitFor ]];do
        ((waitCount+=$delay))

        isAvailable=$(aws rds describe-db-instances --profile $profile \
        --output text --no-cli-pager \
        --db-instance-identifier $instance \
        --query 'DBInstances[*].DBInstanceStatus' \
        )

        echo "$(date +'%F %T %Z') ----Current status: $isAvailable, waiting since ${waitCount}s/$((waitCount/60))min, timeout @: $(($waitFor/60)) min"
        if [ $isAvailable != "available" ]
        then
            sleep $delay
        fi
    done
}

WaitUntilSnapshotIsAvailable(){
    instance=$1;
    isAvailable="";    
    delay=60;
    waitCount=0; 
    waitFor=36000 
    echo "$(date +'%F %T %Z')--Wait until $instance snapshot current status is available"
    while [[ $isAvailable != "available" && $waitCount -lt $waitFor ]];do
        ((waitCount+=$delay))

        isAvailable=$(aws rds describe-db-snapshots --profile $profile \
        --query 'DBSnapshots[*].Status' \
        --db-snapshot-identifier $instance \
        --output text --no-cli-pager)

        echo "$(date +'%F %T %Z') ----Current status: $isAvailable, waiting since ${waitCount}s/$((waitCount/60))min, timeout @: $(($waitFor/60)) min"
        
        if [ $isAvailable != "available" ]
        then
            sleep $delay
        fi
    done
}

WaitUntilRDSIsAvailable $source_db_identifier

#--Create a new RDS snapshot 
aws rds create-db-snapshot --profile $profile --no-cli-pager \
--db-instance-identifier $source_db_identifier \
--db-snapshot-identifier $snapshot_identifier

WaitUntilSnapshotIsAvailable $snapshot_identifier

#--Upgrade the RDS snapshot to the target version, took 34min
aws rds modify-db-snapshot --profile $profile --no-cli-pager \
--db-snapshot-identifier $snapshot_identifier \
--engine-version 13.5

WaitUntilSnapshotIsAvailable $snapshot_identifier

#--Upgrade the RDS snapshot to the target version, took 27min
# aws rds modify-db-snapshot --profile $profile --no-cli-pager \
# --db-snapshot-identifier $snapshot_identifier \
# --engine-version 13.6

# WaitUntilSnapshotIsAvailable $snapshot_identifier

#Get VPC ID, ParameterGroup, Subnet Group from Source RDS instance
read vpc_security_grp_id src_param_grp_name db_subnet_group_id < <(echo $(aws rds describe-db-instances --profile $profile --no-cli-pager \
--db-instance-identifier $source_db_identifier \
| jq -r '.DBInstances[0] 
| ([(.VpcSecurityGroups[]?| select(.Status == "active").VpcSecurityGroupId)]|join(","))
, ([(.DBParameterGroups[]?| select(.ParameterApplyStatus == "in-sync").DBParameterGroupName)]|join(","))
,.DBSubnetGroup.DBSubnetGroupName'
))
vpc_security_grp_id=$(echo $vpc_security_grp_id | tr ',' ' ')
echo "--------------------SOURCE RDS VALUES----------------------
VPC-sg      : $vpc_security_grp_id
ParameterGrp: $src_param_grp_name
SubnetGroup : $db_subnet_group_id
-----------------------------------------------------------"

#--validate the custom parameters, this returns list of parameters that have been modified wrt default parameters
aws rds describe-db-parameters --profile $profile --no-cli-pager \
--db-parameter-group-name $src_param_grp_name \
--query "Parameters[*].[ParameterName,ParameterValue]" \
--source user --output text
	
#--create a new parameter group in the target version
aws rds create-db-parameter-group --profile $profile --no-cli-pager \
--db-parameter-group-name $dest_param_grp_name \
--description "parameters for $dest_param_grp_name" \
--db-parameter-group-family postgres13

#--Apply custom parameters changed in previous parameter group
aws rds modify-db-parameter-group --profile $profile --no-cli-pager \
--db-parameter-group-name $dest_param_grp_name \
--parameters "ParameterName='track_commit_timestamp',ParameterValue=1,ApplyMethod=pending-reboot" \
"ParameterName='rds.logical_replication',ParameterValue=1,ApplyMethod=pending-reboot"

#--Assign new parameter group and restore snapshot with this parameter group, 11min
$(echo "aws rds restore-db-instance-from-db-snapshot --no-cli-pager \
--profile $profile \
--db-instance-identifier $destination_db_identifier \
--db-snapshot-identifier $snapshot_identifier \
--db-parameter-group-name $dest_param_grp_name \
--db-subnet-group-name $db_subnet_group_id \
--vpc-security-group-ids $vpc_security_grp_id \
--availability-zone ap-southeast-1a	\
--no-publicly-accessible \
--no-auto-minor-version-upgrade \
--no-multi-az \
--copy-tags-to-snapshot 
")

# --deletion-protection

WaitUntilRDSIsAvailable $destination_db_identifier

#performance insight, enhanced monitoring enable, Stats enable

#--Get the LSN position from the target instance log
logsfrom=$(date -v-8H '+%s' && echo $EPOCHSECONDS)"000"
rm -f $logpath
for awsfilename in $( aws rds describe-db-log-files --profile $profile --no-cli-pager \
    --db-instance-identifier $destination_db_identifier \
    --file-last-written $logsfrom | jq -r '.DescribeDBLogFiles[] | .LogFileName' 
)
do
    echo "Downloading $awsfilename"
    aws rds download-db-log-file-portion --profile $profile --no-cli-pager \
        --db-instance-identifier $destination_db_identifier \
        --starting-token 0 \
        --output text \
        --log-file $awsfilename >> $logpath
    chmod 755 $logpath
    sleep 2s # add delay to avoid aws throttling
done

#Get the redo LSN no, something like this(175/B0000810) - redo done at 16A/DC000060
cat $logpath | grep redo


#TARGET DATABASE SIDE
CREATE SUBSCRIPTION pglogical_sub01 
CONNECTION 'host=read-replica-testing-shangupta.clj4ceqxrmmj.ap-southeast-1.rds.amazonaws.com port=5432 dbname=northwind user=pgrepuser password=SECRET'
PUBLICATION pglogical_rep01
WITH (
  copy_data = false,
  create_slot = false,
  enabled = false,
  connect = true,
  slot_name = 'pglogical_rep01'
);

# Advance the SUBSCRIPTION
SELECT 'pg_'||oid::text AS "external_id"
FROM pg_subscription 
WHERE subname = 'pglogical_sub01';

# Now advance the subscription to the LSN we got in step 8 - pg_replication_origin_advance(external_id, lsn)
SELECT pg_replication_origin_advance('pg_57414', restart_lsn_of_publisher) ;

# Enable the SUBSCRIPTION
ALTER SUBSCRIPTION pglogical_sub01 ENABLE;
