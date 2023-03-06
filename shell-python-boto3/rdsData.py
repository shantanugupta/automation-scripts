# %%
import numpy as np
import boto3
import os
import pandas as pd

def get_rds_list(aws_session, aws_account_name):
    rds = aws_session.client('rds')
    # Retrieves all regions/endpoints that work with EC2
    Marker=""
    recurse = True
    c=[]

    while(recurse):
        response = rds.describe_db_instances(Marker=Marker)
        instances = response["DBInstances"]

        # %%
        df= pd.DataFrame.from_dict(instances)

        # %%
        out=df.loc[:,['DBInstanceIdentifier'
                    , 'DBInstanceClass'
                    , 'Engine'
                    , 'EngineVersion'
                    , 'AutoMinorVersionUpgrade'
                    , 'PerformanceInsightsEnabled'
                    , 'PreferredMaintenanceWindow'
                    , 'Endpoint'
                    , 'AllocatedStorage'
                    , 'TagList'
                    , 'OptionGroupMemberships'
                    , 'DBParameterGroups'
                    , 'ReadReplicaDBInstanceIdentifiers'
                    , 'DBInstanceStatus'
                    , 'MultiAZ'
                    , 'AvailabilityZone'
                    , 'StorageType'
                    , 'DBSubnetGroup'
                    ]]

        exclude =  ['ZABBIXTH','Terraform']
        #include=['Team', 'Services']
        for r in out.itertuples():
            i = {
              'AWS-Account': aws_account_name
            , 'DBInstanceIdentifier':r.DBInstanceIdentifier
            , 'DBInstanceClass':r.DBInstanceClass
            , 'Engine':r.Engine
            , 'EngineVersion':r.EngineVersion
            , 'AutoMinorVersionUpgrade':r.AutoMinorVersionUpgrade
            , 'PerformanceInsightsEnabled':r.PerformanceInsightsEnabled
            , 'PreferredMaintenanceWindow':r.PreferredMaintenanceWindow
            , 'Endpoint':r.Endpoint['Address']
            , 'AllocatedStorage':r.AllocatedStorage
            #, 'ReadReplicaDBInstanceIdentifiers':r.ReadReplicaDBInstanceIdentifiers
            , 'DBInstanceStatus':r.DBInstanceStatus
            , 'MultiAZ':r.MultiAZ
            , 'AvailabilityZone':r.AvailabilityZone
            , 'StorageType':r.StorageType
            , 'DBSubnetGroupName':r.DBSubnetGroup['DBSubnetGroupName']
            }
            [i.update({t['Key'].strip():t['Value']}) for t in r.TagList if t['Key'] not in exclude]

            c.append(i)

        if 'Marker' in response.keys():
            Marker = response['Marker']
        else:
            print('Marker missing - no more data to fetch')
            recurse=False
    return c

def accumulate_rds_from_all_accounts():
    environments=["cn", "prod", "dev"]
    rds_list = []

    outputFile=f"./data/rds_instances.csv"
    if os.path.exists(outputFile):
        os.remove(outputFile)

    for env in environments:
        print (f"Pulling data for {env}")
        profile=f"{env}-long-term-mfa"
        aws_session = boto3.Session(profile_name=profile)
        data = get_rds_list(aws_session, env)
        rds_list +=data

    pd.DataFrame(rds_list).to_csv(outputFile, mode='a')

accumulate_rds_from_all_accounts()
