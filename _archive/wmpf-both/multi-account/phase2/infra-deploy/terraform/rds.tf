resource "aws_db_subnet_group" "platform" {
  count = var.deployment.rds ? 1 : 0

  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = [for az in local.two_azs : aws_subnet.rds[az].id]

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group"
  }
}

resource "aws_db_instance" "platform" {
  count = var.deployment.rds ? 1 : 0

  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.deployment.kms ? aws_kms_key.application[0].arn : null

  db_name  = var.rds_database_name
  username = var.rds_username
  port     = 5432

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null

  db_subnet_group_name   = aws_db_subnet_group.platform[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = false
  multi_az               = var.rds_multi_az

  backup_retention_period = var.rds_backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot       = true

  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.name_prefix}-final-snapshot" : null

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}
