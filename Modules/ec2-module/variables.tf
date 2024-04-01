variable "ami" {
  description = "The AMI to use for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "The type of instance to start"
  type        = string
}

variable "availability_zone" {
  description = "The availability zone in which to launch the instance and EBS volume"
  type        = string
}

variable "docker_image" {
  description = "The Docker image to use for the user data"
  type        = string
}

variable "my_vpc_id" {
  description = "The ID of the VPC in which to create the Route 53 zone"
  type        = string
  
}