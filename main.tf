
provider "aws" {
    region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "test_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "Test"
    }
}

resource "aws_s3_bucket" "test-db-bucket" {
    bucket_prefix = "test-db-bucket"
    acl    = "private"
    versioning {
        enabled = true
    }
}

resource "aws_s3_bucket_object" "database_obj" {
    bucket = aws_s3_bucket.test-db-bucket.id
    key = "database.db"
    source = "${path.module}/database.db"
}

resource "aws_iam_role" "db_function_role" {
    name = "Test-DB-Role"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "db_function_role_policy" {
    name = "Test-DB-Policy"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
            Effect = "Allow"
            Action = [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
            Resource = [
                "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.db_function.function_name}:*",
                "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.deadlock_fix_function.function_name}:*"
            ]
        },
        {
            Effect = "Allow",
            Action = [
                "s3:PutObject",
                "s3:GetObjectAcl",
                "s3:GetObject",
                "s3:PutObjectVersionAcl",
                "s3:PutObjectAcl",
                "s3:GetObjectVersion"
            ]
            Resource = [
                "${aws_s3_bucket.test-db-bucket.arn}/*"
            ]
        },
        {
            Effect = "Allow"
            Action = [
                "ec2:DeleteSecurityGroup",
                "ec2:CreateSecurityGroup",
                "ec2:CreateTags"
            ]
            Resource = [
                "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/*",
                "${aws_vpc.test_vpc.arn}"
            ]
        },
        {
            Effect = "Allow"
            Action = [
                "ec2:DescribeSecurityGroups"
            ]
            Resource = [
                "*"
            ]
        }
    ]
})
}

resource "aws_iam_role_policy_attachment" "test-db-policy-attachment" {
    role = aws_iam_role.db_function_role.name
    policy_arn = aws_iam_policy.db_function_role_policy.arn
}

data "archive_file" "db_function" {
    type = "zip"
    source_file = "${path.module}/db_function/lambda_function.py"
    output_path = "${path.module}/db_function.zip"
}

resource "aws_cloudwatch_log_group" "db_function_log_group" {
    name = "/aws/lambda/${aws_lambda_function.db_function.function_name}"
}

resource "aws_lambda_function" "db_function" {
    function_name = "test-db-function"
    role = aws_iam_role.db_function_role.arn
    runtime = "python3.8"
    handler = "lambda_function.lambda_handler"
    filename = data.archive_file.db_function.output_path
    source_code_hash = data.archive_file.db_function.output_base64sha256
    timeout          = 10

    environment {
        variables = {
            vpc_id = aws_vpc.test_vpc.id
            bucket_name = aws_s3_bucket.test-db-bucket.id
        }
    }
}

resource "aws_cloudwatch_event_rule" "deadlock_function_trigger" {
    name = "test-db-event-rule"
    schedule_expression = "cron(*/15 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "deadlock_function_target" {
    rule = aws_cloudwatch_event_rule.deadlock_function_trigger.name
    arn = aws_lambda_function.deadlock_fix_function.arn
}

data "archive_file" "deadlock_fix_function" {
    type = "zip"
    source_file = "${path.module}/deadlock_fix/lambda_function.py"
    output_path = "${path.module}/deadlock_fix_function.zip"
}

resource "aws_cloudwatch_log_group" "deadlock_fix_function_log_group" {
    name = "/aws/lambda/${aws_lambda_function.deadlock_fix_function.function_name}"
}

resource "aws_lambda_function" "deadlock_fix_function" {
    function_name = "test-db-function-deadlock-fix"
    role = aws_iam_role.db_function_role.arn
    runtime = "python3.8"
    handler = "lambda_function.lambda_handler"
    filename = data.archive_file.deadlock_fix_function.output_path
    source_code_hash = data.archive_file.deadlock_fix_function.output_base64sha256
    timeout          = 900

    environment {
        variables = {
            vpc_id = aws_vpc.test_vpc.id
        }
    }
}