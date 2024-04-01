module "ec2-module" {
  source = "./Modules/ec2-module" 
  ami             = "ami-04dfd853d88e818e8"
  instance_type   = "t3.medium"
  availability_zone = "eu-central-1a" 
  docker_image = "rabbitmq:3.13-management"
  my_vpc_id =  "vpc-02249be70919abaa2"
}


