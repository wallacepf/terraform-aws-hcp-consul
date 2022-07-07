data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-hirsute-21.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group_rule" "allow_ssh_inbound" {
  count       = length(var.allowed_ssh_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = var.allowed_ssh_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_nomad_inbound" {
  count       = length(var.allowed_http_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = 8081
  to_port     = 8081
  protocol    = "tcp"
  cidr_blocks = var.allowed_http_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_security_group_rule" "allow_http_inbound" {
  count       = length(var.allowed_http_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = var.allowed_http_cidr_blocks

  security_group_id = var.security_group_id
}

resource "aws_instance" "nomad_host" {
  count                       = 1
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  associate_public_ip_address = false
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    setup = base64gzip(templatefile("${path.module}/templates/setup.sh", {
      consul_config    = var.client_config_file,
      consul_ca        = var.client_ca_file,
      consul_acl_token = var.root_token,
      consul_version   = var.consul_version,
      consul_service = base64encode(templatefile("${path.module}/templates/service", {
        service_name = "consul",
        service_cmd  = "/usr/bin/consul agent -data-dir /var/consul -config-dir=/etc/consul.d/",
      })),
      nomad_service = base64encode(templatefile("${path.module}/templates/service", {
        service_name = "nomad",
        service_cmd  = "sudo /usr/bin/nomad agent -dev-connect -consul-token=${var.root_token}",
      })),
      hashicups  = base64encode(file("${path.module}/templates/hashicups.nomad")),
      nginx_conf = base64encode(file("${path.module}/templates/nginx.conf")),
      vpc_cidr   = var.vpc_cidr
    })),
  })

  tags = {
    Name = "${random_id.id.dec}-hcp-nomad-host"
  }

  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
  }
}

resource "random_id" "id" {
  prefix      = "consul-client"
  byte_length = 8
}

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "nomad-host-elb"

  load_balancer_type = "network"

  vpc_id  = var.vpc_id
  subnets = var.elb_public_subnets

  target_groups = [
    {
      name_prefix      = "fe-"
      backend_protocol = "TCP"
      backend_port     = 80
      target_type      = "instance"
      targets = {
        frontend = {
          target_id = aws_instance.nomad_host[0].id
          port      = 80
        }
      }
    },
    {
      name_prefix      = "nmd-"
      backend_protocol = "TCP"
      backend_port     = 8081
      target_type      = "instance"
      targets = {
        nomad = {
          target_id = aws_instance.nomad_host[0].id
          port      = 8081
        }
      }
    },
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 0
    },
    {
      port               = 8081
      protocol           = "TCP"
      target_group_index = 1
    },
  ]
}