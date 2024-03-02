variable "aws_region" {
  default = "us-east-1"
}
 
variable "s3_bucket_name" {
  default = "image-bucket-casestudy6"
}

variable "environment_id" {
 default = "dev"
}

variable "ami_id" {
 default = "ami-0440d3b780d96b29d"
}

variable "instance_type" {
 default = "t2.micro"
}

variable "ec2_instances" {
  default = 2
}

variable "cidr_block" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}