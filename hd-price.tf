resource "aws_kms_key" "hd_price_timestream_kms_key" {
    description = "TimeStream encryption key"
    key_usage = "ENCRYPT_DECRYPT"
    multi_region = false
}

resource "aws_kms_alias" "hd_price_timestream_alias" {
    name = "alias/hd-price"
    target_key_id = aws_kms_key.hd_price_timestream_kms_key.arn
}

resource "aws_timestreamwrite_database" "hd_price_database" {
    database_name = "hd-price"
    kms_key_id = aws_kms_key.hd_price_timestream_kms_key.arn
    tags = {
        Name = "hd-price"
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

# resource "aws_s3_bucket" "code_bucket" {
#     bucket = "code.tonytsang.com"
#     acl = "private"

#     tags = {
#         Name = "Code Bucket"
#     }

#     versioning {
#         enabled = true
#     }
# }

resource "aws_s3_bucket_object" "fetcher_code" {
    bucket = "code.tonytsang.com"
    key = "hdprice.zip"
    server_side_encryption = "aws:kms"
    kms_key_id = aws_kms_key.hd_price_timestream_kms_key.arn
}

resource "aws_lambda_function" "fetch_price" {
    function_name = "hd-price"
    s3_bucket = "code.tonytsang.com"
    s3_key = "hdprice.zip"
    architectures = ["arm64"]
    memory_size = "128"
    runtime = "nodejs14.x"
    handler = "index.handler"
    timeout = "300"
    role = aws_iam_role.role_for_hd_price.arn
}

resource "aws_cloudwatch_log_group" "hd_price_log_group" {
    name = "/aws/lambda/hd-price"
    retention_in_days = "30"
    # kms_key_id = aws_kms_key.hd_price_timestream_kms_key.arn
}

resource "aws_iam_role" "role_for_hd_price" {
    name = "hd-price-role"
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
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        ${aws_cloudwatch_log_group.hd_price_log_group.arn}
      ]
    },
    {
      "Effect": "Allow",
      "Action": "timestream:WriteRecords",
      "Resource": [
         ${aws_timestreamwrite_table.hd_prices.arn}
      ]
    }
  ]
}
EOF
}

resource "aws_cloudwatch_event_rule" "trigger_daily" {
    name = "daily-fetch-hd-price"
    description = "Fetch hd prices daily"
    schedule_expression = "cron(0 12 * * * *)"
}

resource "aws_cloudwatch_event_target" "trigger_target" {
    arn = aws_lambda_function.fetch_price.arn
    rule = aws_cloudwatch_event_rule.trigger_daily.id
}