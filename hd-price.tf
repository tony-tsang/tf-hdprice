locals {
    function_name = "hd-price"
}

data "aws_kms_key" "hd_price_timestream_kms_key" {
    key_id = "alias/${local.function_name}"
}

resource "aws_timestreamwrite_database" "hd_price_database" {
    database_name = local.function_name
    kms_key_id = data.aws_kms_key.hd_price_timestream_kms_key.arn
    tags = {
        Name = local.function_name
    }
}

resource "aws_timestreamwrite_table" "hd_prices" {
    database_name = aws_timestreamwrite_database.hd_price_database.database_name
    table_name = "hd-prices"

    retention_properties {
      magnetic_store_retention_period_in_days = 1825
      memory_store_retention_period_in_hours = 1
    }

    tags = {
        Name = "hd-prices"
    }
}

resource "aws_lambda_function" "fetch_price" {
    function_name = local.function_name
    s3_bucket = "code.tonytsang.com"
    s3_key = "hdprice.zip"
    architectures = ["arm64"]
    memory_size = "128"
    runtime = "nodejs16.x"
    handler = "index.handler"
    timeout = "300"
    role = aws_iam_role.role_for_hd_price.arn

    depends_on = [

    ]
}

resource "aws_cloudwatch_log_group" "hd_price_log_group" {
    name = "/aws/lambda/${local.function_name}"
    retention_in_days = "30"
    # kms_key_id = data.aws_kms_key.hd_price_timestream_kms_key.arn
}

data "aws_iam_user" "robot_user" {
    user_name = "robot-user"
}

resource "aws_iam_role" "role_for_hd_price" {
    name = "hd-price-role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Sid    = ""
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            }
        ]
    })
}

resource "aws_iam_role_policy" "permissions_for_hd_price_role" {
    name = "hd-price-policy"
    role = aws_iam_role.role_for_hd_price.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = [
                    "timestream:Select",
                    "timestream:SelectValues",
                    "timestream:WriteRecords",
                    "timestream:ListMeasures",
                    "timestream:ListTables",
                    "timestream:ListDataabses",
                    "timestream:DescribeEndpoints",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Effect = "Allow"
                Resource = "*"
            }
        ]
    })
}

resource "aws_cloudwatch_event_rule" "trigger_daily" {
    name = "daily-fetch-hd-price"
    description = "Fetch hd prices daily"
    schedule_expression = "cron(0 4 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_target" {
    arn = aws_lambda_function.fetch_price.arn
    rule = aws_cloudwatch_event_rule.trigger_daily.name
    target_id = "fetch_price"
}

resource "aws_lambda_permission" "allow_cloudwatch_trigger" {
    statement_id = "AllowExecutionFromEventBridge"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.fetch_price.function_name
    principal = "events.amazonaws.com"
    source_arn = aws_cloudwatch_event_rule.trigger_daily.arn
}