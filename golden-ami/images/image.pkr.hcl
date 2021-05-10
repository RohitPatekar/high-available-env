variable "region" {
  type    = string
  default = "us-east-1"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "golden-ami" {
  ami_name      = "golden-ami-${local.timestamp}"
  instance_type = "t2.micro"
  region       = var.region
  iam_instance_profile = "AWSAdminRole"
  source_ami_filter {
        filters = {
          virtualization-type = "hvm"
          name = "amzn2-ami-hvm-2.0.*-x86_64-gp2"
          root-device-type: "ebs"
        }
        owners = ["amazon"]
        most_recent = true
      }
  
  ssh_username = "ec2-user"
}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.amazon-ebs.golden-ami"]

  provisioner "shell" {
    script = "../scripts/setup_tomcat.sh"
  }
  
  provisioner "file" {
  source      = "../scripts/amazon-cloudwatch-agent.json"
  destination = "/tmp/amazon-cloudwatch-agent.json"
  }
  
  provisioner "shell" {
  script = "../scripts/setup_cloudwatch.sh"
  }
  
}
