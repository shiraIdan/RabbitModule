#!/bin/bash
# Docker Installation
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install docker
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
# Set up perms
sudo usermod -aG docker $USER


# Create EBS volume mount for RabbitMQ to persist the data
sudo sed -i '$a/dev/xvda /var/lib/rabbitmq/ auto defaults,nofail 0 2' /etc/fstab && sudo mount -a



# Create the configuration file
cat << ZOF > /rabbitconf/config.conf
loopback_users.guest = false
listeners.tcp.default = 5672
cluster_formation.peer_discovery_backend = aws
cluster_formation.aws.region = eu-central-1
cluster_formation.aws.use_autoscaling_group = true
cluster_formation.aws.access_key_id = ${aws_access_key_id}
cluster_formation.aws.secret_key = ${aws_secret_access_key}
ZOF

# Create a volume and create a temp container and move the configuration file to volume
docker run -d --name temp-container --rm -v rabbit_config_volume:/rabbit_config_volume alpine
docker cp /rabbitmq/config.conf temp-container:/rabbit_config_volume/
docker stop temp-container



# Create a volume and run the rabbitmq container 
docker volume create rabbit_config_volume
docker run -d --name rabbit \
  --network host \
  -v rabbit_config_volume:/rabbit_config_volume/ \
  -e RABBITMQ_CONFIG_FILE=/rabbit_config_volume/config.conf \
  -e RABBITMQ_ERLANG_COOKIE=WSPp6YtVS41KJQBYZRPlSR+qAT6lRPQhd7BfhRfe \
  rabbitmq:3.13.0 \
  rabbitmq-plugins --offline enable rabbitmq_peer_discovery_aws


# addtional setup
docker exec -d rabbit rabbitmq-server
# Enabling plugins
rabbitmq-plugins enable rabbitmq_management
rabbitmq-plugins --offline enable rabbitmq_peer_discovery_aws



EOF 


docker run -d --name rabbit \
  --network host \
    -v rabbit_config_volume:/rabbitconf/ \

    rabbitmq:3.13.0 
    