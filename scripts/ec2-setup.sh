#!/usr/bin/env bash
set -euo pipefail

echo "Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

echo "Installing prerequisites (Java 17 for Jenkins, curl, git, nginx)..."
sudo apt-get install -y openjdk-17-jre curl git nginx ca-certificates gnupg

echo "Installing Docker Engine..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Installing Jenkins..."
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y jenkins

echo "Granting Jenkins user Docker & Nginx reload permissions..."
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu
echo "jenkins ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/nginx/conf.d/kanban-upstream.conf, /usr/sbin/nginx" | sudo tee /etc/sudoers.d/jenkins-nginx

sudo systemctl enable --now docker
sudo systemctl enable --now jenkins
sudo systemctl enable --now nginx

echo "=========================================="
echo "Setup Complete!"
echo "Initial Jenkins Admin Password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo "=========================================="
