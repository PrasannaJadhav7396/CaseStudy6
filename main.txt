# Module for vpc_dev setup
module "vpc_dev_dev" {
  source = "terraform-aws-modules/vpc_dev/aws"
 
  name                 = "${var.environment_id}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  private_subnets      = var.cidr_block
  tags = {
    Environment = "dev"
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "ec2_role" {
  name               = "${var.environment_id}-ec2-s3-access-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
 
# S3 bucket
resource "aws_s3_bucket" "source_image_bucket" {
  bucket = "${var.environment_id}-${var.s3_bucket_name}"
  acl    = "private"
 
  # To deny all public access as we will access via vpc_dev endpoint
  force_destroy = true
 
  lifecycle {
    prevent_destroy = false
  }

  versioning {
    enabled = true
  }

  tags = {
    Name = "Dev Source Image Bucket"
  }
}

# IAM policy for S3 access
resource "aws_iam_policy" "s3_policy" {
  name = "${var.environment_id}-s3-access-policy"
 
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.source_image_bucket.bucket}/*"
    }
  ]
}
EOF
}
 
# Attach policy to role
resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

# S3 vpc_dev Endpoint
resource "aws_vpc_dev_endpoint" "s3_vpc_endpoint" {
  vpc_dev_id        = module.vpc_dev.vpc_dev_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_dev_endpoint_type = "Interface"
 
  subnet_ids = module.vpc_dev.private_subnets
 
  security_group_ids = [module.vpc_dev.default_security_group_id]
 
  private_dns_enabled = true
}
 
# Create security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = "${var.environment_id}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.vpc_dev.id

  # Add inbound rule to allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
 
# EC2 instance
resource "aws_instance" "dev_instances" {
  count           = var.ec2_instances  
  ami             = var.ami_id
  instance_type   = var.instance_type
  subnet_id       = element(var.cidr_block, count.index)
  
  iam_instance_profile = aws_iam_role.ec2_role.name
 
  # Security group allowing outbound access
  security_groups = ["ec2_sg"]
 
  # User data to install CloudWatch agent
  user_data = <<-EOF
              #!/bin/bash
              sudo yum install -y amazon-cloudwatch-agent
			  mkdir /opt/images && mkdir /opt/s3_copy_script
			  
			  cat > /opt/s3_copy_script/copy_from_s3.sh << 'SCRIPT'
			  #!/bin/bash
			  s3_bucket_name=dev-image-bucket-casestudy6
			  # Set AWS region
			  export AWS_DEFAULT_REGION=us-east-1
			  # Read files from S3 bucket
			  aws s3 sync s3://$s3_bucket_name /opt/images			  
			  SCRIPT
			  chmod +x /opt/images/copy_from_s3.sh
			  
			  # cron to run the script every day at 7 AM
			  echo "0 7 * * * root /opt/images/copy_from_s3.sh" | sudo tee -a /etc/crontab
			  sudo service crond restart
              EOF
}

# CloudWatch Logs agent configuration
resource "aws_cloudwatch_log_group" "dev_ec2_group" {
  name = "/var/log/messages"
}

# CloudWatch Log Stream  
resource "aws_cloudwatch_log_stream" "dev_ec2_log_group" {
  name           = "${var.environment_id}-log-stream"
  log_group_name = aws_cloudwatch_log_group.dev_ec2_group.name
}

# CloudWatch Subscription Filter 
resource "aws_cloudwatch_log_subscription_filter" "dev_ec2_log_subscription" {
  name            = "${var.environment_id}-log-subscription"
  log_group_name  = aws_cloudwatch_log_group.dev_ec2_group.name
  filter_pattern  = ""
  destination_arn = aws_cloudwatch_log_stream.dev_ec2_log_group.arn
}
 
# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "${var.environment_id}-cloudtrail-bucket-name"
  acl    = "private"
}

# CloudWatch Logs setup for CloudTrail logs
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  name = "/aws/cloudtrail/cloudtrail-ec2-s3"
}
 
# CloudTrail setup for EC2 and S3
resource "aws_cloudtrail" "cloudtrail_ec2_s3" {
  name                          = "${var.environment_id}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.bucket
  is_multi_region_trail         = true
  enable_log_file_validation    = true
 
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
	# S3 bucket
    data_resource {
      type  = "AWS::S3::Object"
      values = ["arn:aws:s3:::source_image_bucket/*"] 
    }
    
	# EC2 instance
    data_resource {
      type  = "AWS::EC2::Instance"
      values = ["arn:aws:ec2:*:*:instance/*"]
    }
  }
 
  cloud_watch_logs_group_arn = aws_cloudwatch_log_group.cloudtrail_logs.arn
}
