import json
import time
import boto3
import os

client = boto3.client("ec2")
vpc_id = os.environ["vpc_id"]

def lambda_handler(event, context):

    while True:
        resp = client.describe_security_groups(Filters=[{"Name": "group-name", "Values": ["DistributedLockTest"]}])
        if resp is not None:
            if "SecurityGroups" in resp:
                for sg in resp["SecurityGroups"]:
                    if "GroupName" in sg and sg["GroupName"] == "DistributedLockTest":
                        # Found lock security group
                        if "Tags" in sg:
                            for tag in sg["Tags"]:
                                if "Key" in tag and tag["Key"] == "CreateTime" and "Value" in tag:
                                    createTime = float(tag["Value"])
                                    currentTime = time.time()
                                    if currentTime - createTime >= 10:
                                        client.delete_security_group(GroupId=sg["GroupId"])
        time.sleep(1)

