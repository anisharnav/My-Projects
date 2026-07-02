# SERVER2: 'NODE-SERVER' (with Docker & Kubernetes)
# STEP1: CREATING A SECURITY GROUP FOR DOCKER-K8S
# Description: K8s requires ports 22, 80, 443, 6443, 8001, 10250, 30000-32767
resource "aws_security_group" "my_security_group2" {
  name        = "my-security-group2"
  description = "Allow K8s ports"

  # SSH Inbound Rules
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH Outbound Rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# STEP2: CREATE A K8S EC2 INSTANCE USING EXISTING PEM KEY
# Note: i. First create a pem-key manually from the AWS console
#      ii. Copy it in the same directory as your terraform code
resource "aws_instance" "my_ec2_instance2" {
  ami                    = "ami-0b6d9d3d33ba97d99"
  instance_type          = "c7i-flex.large" # K8s requires min 2CPU & 4G RAM
  vpc_security_group_ids = [aws_security_group.my_security_group2.id]
  key_name               = "My_Key" # paste your key-name here, do not use extension '.pem'

  # Consider EBS volume 30GB
  root_block_device {
    volume_size = 30    # Volume size 30 GB
    volume_type = "gp2" # General Purpose SSD
  }

  tags = {
    Name = "MASTER-SERVER"
  }

  # STEP3: USING REMOTE-EXEC PROVISIONER TO INSTALL TOOLS
  provisioner "remote-exec" {
    # ESTABLISHING SSH CONNECTION WITH EC2
    connection {
      type        = "ssh"
      private_key = file("./My_Key.pem") # replace with your key-name
      user        = "ubuntu"
      host        = self.public_ip
    }

      inline = [
      "sleep 200",

      # Disable Swap
      "swapoff -a",
      "sudo sed -i '/ swap / s/^\\(.*\\)$/#\\1/g' /etc/fstab",

      # Forwarding IPv4 and letting iptables see bridged traffic
      "cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf",
      "overlay",
      "br_netfilter",
      "EOF",

      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",

      # sysctl params required by setup, params persist across reboots
      "cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf",
      "net.bridge.bridge-nf-call-iptables  = 1",
      "net.bridge.bridge-nf-call-ip6tables = 1",
      "net.ipv4.ip_forward                 = 1",
      "EOF",

      # Apply sysctl params without reboot
      "sudo sysctl --system",

      # Verify that the br_netfilter, overlay modules are loaded by running the following commands:
      "lsmod | grep br_netfilter",
      "lsmod | grep overlay",

      # Verify that the net.bridge.bridge-nf-call-iptables, net.bridge.bridge-nf-call-ip6tables, and net.ipv4.ip_forward system variables are set to 1 in your sysctl config by running the following command:
      "sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward",

      # Install container runtime
      "curl -LO https://github.com/containerd/containerd/releases/download/v1.7.14/containerd-1.7.14-linux-amd64.tar.gz",
      "sudo tar Cxzvf /usr/local containerd-1.7.14-linux-amd64.tar.gz",
      "curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service",
      "sudo mkdir -p /usr/local/lib/systemd/system/",
      "sudo mv containerd.service /usr/local/lib/systemd/system/",
      "sudo mkdir -p /etc/containerd",
      "containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's/SystemdCgroup \\= false/SystemdCgroup \\= true/g' /etc/containerd/config.toml",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now containerd",

      # Check that containerd service is up and running
      "systemctl status containerd --no-pager",


      # Install runc
      "curl -LO https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64",
      "sudo install -m 755 runc.amd64 /usr/local/sbin/runc",


      # Install cni plugin
      "curl -LO https://github.com/containernetworking/plugins/releases/download/v1.5.0/cni-plugins-linux-amd64-v1.5.0.tgz",
      "sudo mkdir -p /opt/cni/bin",
      "sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.5.0.tgz",


      # Install kubeadm kubelet and kubectl
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gpg",

      "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list",

      "sudo apt-get update",
      "sudo apt-get install -y kubelet=1.29.6-1.1 kubeadm=1.29.6-1.1 kubectl=1.29.6-1.1 --allow-downgrades --allow-change-held-packages",
      "sudo apt-mark hold kubelet kubeadm kubectl",

      "kubeadm version",
      "kubelet --version",
      "kubectl version --client",


      # Configure crictl to configure with containerd
      "sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock",

      # Initialize control plane
      "sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=${self.private_ip} --node-name master",


      # Prepare kubeconfig
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",


      # Install calico
      "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml",
      "curl https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml -O",
      "kubectl apply -f custom-resources.yaml",
      ]
    }

}

# STEP3: OUTPUT PUBLIC IP OF EC2 INSTANCE
output "NODE_SERVER_PUBLIC_IP" {
  value = aws_instance.my_ec2_instance2.public_ip
}

# STEP4: OUTPUT PRIVATE IP OF EC2 INSTANCE
output "NODE_SERVER_PRIVATE_IP" {
  value = aws_instance.my_ec2_instance2.private_ip
}
