# %%
from ast import Mult
from textwrap import indent
from tkinter.tix import Tree
import numpy as np
import boto3
import os
import pandas as pd
import json
import datetime
import logging
from common import datetimeConverter

logging.basicConfig(format='%(asctime)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p')

environment="dev"
os.environ['AWS_PROFILE'] = environment+ "-long-term-mfa"
os.environ['AWS_DEFAULT_REGION'] = "ap-southeast-1"
os.environ['AWS_DEFAULT_OUTPUT'] = "yaml"
status = ""
rds = boto3.client('rds')



def readRDS(DBInstanceIdentifier):
    instances = rds.describe_db_instances(DBInstanceIdentifier=DBInstanceIdentifier)
    instance = instances['DBInstances'][0]

    ## print output
    output = json.dumps(instance, indent=3, default = datetimeConverter)

    ## print output to file 
    file = open('./rds/' + DBInstanceIdentifier+'.json', 'w')
    json.dump(instance, file, indent=3, default=datetimeConverter)
    
    param = prepareParametersForReplica(instance)
    return param

def prepareParametersForReplica(instance):
    manualParameters={
        "DBInstanceIdentifier":""
        ,"SourceDBInstanceIdentifier":""
        ,"AvailabilityZone" : "ap-southeast-1a"
        ,"VpcSecurityGroupIds" : []
        ,"EnablePerformanceInsights" : True
        ,"Tags":[]
    }

    extractParameters = [
        "MultiAZ"
        ,"AutoMinorVersionUpgrade"
        ,"CopyTagsToSnapshot"
        ,"StorageType"
        ,"MonitoringInterval"
        ,"DeletionProtection"
        ,"PubliclyAccessible"
    ]
    
    for i in instance.items():
        k = i[0]
        v = i[1]
        
        if k == 'DBInstanceIdentifier':
            manualParameters.update({"DBInstanceIdentifier": v+ "-replica"})
            manualParameters.update({"SourceDBInstanceIdentifier": v })
        
        elif k == 'PerformanceInsightsEnabled':
            manualParameters.update({"EnablePerformanceInsights": v})
            if v ==True:
                manualParameters.update({"PerformanceInsightsRetentionPeriod": 7})

        elif k in extractParameters and type(k) is str:
            manualParameters.update({k:v})
            
        elif k == "TagList":
            manualParameters.update({"Tags":v})
        
        # elif k=="DBSubnetGroup":
        #     manualParameters.update({"DBSubnetGroupName":v["DBSubnetGroupName"]})

        elif k == "VpcSecurityGroups":
            for vpc in v:
                manualParameters["VpcSecurityGroupIds"].append(vpc["VpcSecurityGroupId"])

    return manualParameters

def createReplicaRDS(DBInstanceIdentifier):
    try:
        parameters = readRDS(DBInstanceIdentifier=DBInstanceIdentifier)
        status = rds.create_db_instance_read_replica(**parameters)
        
        filepath='./rds/output-' + parameters['DBInstanceIdentifier']+'.json'
        file = open(filepath, 'w')
        
        json.dump(status, file, indent=3, default=datetimeConverter)
        logging.info('Output here: '+ filepath )

    except BaseException as err:
        logging.error(err)
        status = err
    return status

# %%
status = createReplicaRDS("read-replica-testing-shangupta")

print(status)