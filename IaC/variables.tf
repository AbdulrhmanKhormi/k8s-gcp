variable "project_id" {
  type    = string
  default = "brave-standard-467008-u1"
}

variable "image" {
  type    = string
  default = "projects/debian-cloud/global/images/family/debian-12"
}

variable "region" {
  type    = string
  default = "europe-west3"
}

variable "zone" {
  type    = string
  default = "europe-west3-a"
}

variable "startup_script" {
  type    = string
  default = <<-EOT
#!/bin/bash
set -e

# Update and upgrade system packages
sudo apt-get update
sudo apt-get upgrade -y

sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable IPv4 forwarding
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system

sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release gpg

curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list


# Update package index and install kubelet, kubeadm and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

# Install additional packages
sudo apt-get install -y open-iscsi dmsetup nfs-common

EOF

chmod +x /tmp/start.sh
/tmp/start.sh
EOT
}
