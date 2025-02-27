output "host_id" {
  value = aws_instance.nomad_host[0].id
}

output "public_ip" {
  value = aws_instance.nomad_host[0].public_ip
}

output "private_ip" {
  value = aws_instance.nomad_host[0].private_ip
}

output "nlb_dns" {
  value = module.nlb.lb_dns_name
}