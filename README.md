# AWSServerlessDB

This is a serverless relational database

The database is stored in S3. Lambda functions pull the database from S3 and run queries against it. If the query is editing the database the first thing the lambda function does is acquire a lock to synchronize changes to prevent multiple changes from stepping on eachother. In this case to implement the lock I am using a Security Group. When you make a request to create a Security Group it is an atomic operation. If two requests are made to create a single Security Group 1 will receive a sucess message and the other will get an error. I use the Security Group ID as the lock and to release the lock the lambda function deletes the Security Group. A lambda that fails to get the lock sleeps for a second and then trys again. To prevent deadlock a separate lambda function runs and checks in on the Security Group. The Security Group has a tag which states the time it was created. If it has existed too long the lambda will delete the security group freeing up the lock for another lambda to use.

The end user using this database will want to talk with the lambda by the name "test-db-function". The lambda called "test-db-function-deadlock-fix" helps prevent deadlock.

To use the database you need to call the "test-db-function" lambda and pass a SQL query. Below is a sample lambda test event.

```
{
    "query": "SELECT * FROM test"
}
```

How to expand upon this.
- You could put API Gateway infront and use an authorizor and/or an API Key to restrict access. Then your application/users can communicate with the API Gateway.
- You could have queries from an application get written to an SQS queue which trigger this lambda to execute the queries.


Known Limitations
- Currently the Database is limited to 512 MB. This is due to the max size of the tmp storage on the lambda function. Also if you have a large database it is going to take a while to copy to and from S3 which is going to make the lambda's take longer to run.

Possible Optimizations
- To boost read operations possibly have the lambda check if it is a warm container that already has a copy of the database on it. If it does check to see how old the version of the database is and if its not too old run queies based on that db otherwise fetch a new copy.
- To boost both read and write operations possibly limit the DB size by having multiple DB files. Each one for a different table.
- Another possible optimization is to use EFS instead of S3.

Latency (Rough numbers based on my testing. I did the test by running test events directly in Lambda. Your numbers may vary)
- Cold read with a small database takes around 300-500 milliseconds
- Warm node read with a small database takes around 100-200 milliseconds
- Cold write with a small database takes around 1 - 1.5 seconds
- Warm write with a small database takes around 800 miliseconds to 1 second

