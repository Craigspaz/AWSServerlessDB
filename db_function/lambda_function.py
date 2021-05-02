import json
import sqlite3
import time
import boto3
import os

client = boto3.client("ec2")
s3_client = boto3.client("s3")
vpc_id = os.environ["vpc_id"]
bucket_name = os.environ["bucket_name"]

def acquireLock():
    print("Acquiring Lock...")
    while True:
        try:
            resp = client.create_security_group(Description="DistributedLockTest", GroupName="DistributedLockTest", VpcId=vpc_id, TagSpecifications=[{"ResourceType": "security-group","Tags": [{"Key": "CreateTime","Value": str(time.time())}]}])
            if resp["ResponseMetadata"]["HTTPStatusCode"] == 200:
                return resp["GroupId"]
        except:
            print("Failed to acquire lock. Backing off and trying again...")
            time.sleep(1)

def releaseLock(lock):
    print("Releasing Lock...")
    while True:
        try:
            client.delete_security_group(GroupId=lock)
            return None
        except:
            print("Failed to release lock. Trying again...")
            time.sleep(1)
    

def lambda_handler(event, context):

    # Get Query
    query = event["query"].strip("'")
    print("Query: " + str(query))
    
    readOnly = True
    if "CREATE" in query.upper() or "INSERT" in query.upper() or "UPDATE" in query.upper(): # very rough check. May not be accurate
        readOnly = False
    
    if readOnly == False:
        lock = acquireLock()

    output = ""
    try:
        s3_client.download_file(bucket_name, "database.db", "/tmp/database.db")
        
        # Run Query
        connection = sqlite3.connect("/tmp/database.db")
        cursor = connection.cursor()
        cursor.execute(query)
        connection.commit()
        output = cursor.fetchall()
        connection.close()
        
        if readOnly == False:
            dbFile = open("/tmp/database.db", "rb")
            s3_client.put_object(Bucket=bucket_name, Key="database.db", Body=dbFile.read())
            dbFile.close()
            releaseLock(lock)
    except:
        if readOnly == False:
            releaseLock(lock)
    
    return {
        'statusCode': 200,
        'body': output
    }
