resource "aws_kms_key" "hd_price_timestream_kms" {
    description = "TimeStream encryption key"
    key_usage = "ENCRYPT_DECRYPT"
    multi_region = false
}

resource "aws_timestreamwrite_database" "hd_price_database" {
    database_name = "hd-price"
    kms_key_id = aws_kms_key.hd_price_timestream_kms.arn
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