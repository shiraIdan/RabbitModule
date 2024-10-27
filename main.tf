module "ec2-module" {
  source            = "./Modules/ec2-module"
  ami               = "ami-0e86e20dae9224db8"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  docker_image      = "rabbitmq:3.13-management"
  my_vpc_id         = "vpc-0ce7ca8cbeba6b3d4"
  subnet_id         = "subnet-0b1cad40369f5a5dd"
}


