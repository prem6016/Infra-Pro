output "instance_id" {
  description = "EC2 instance id"
  value       = aws_instance.dev_vm.id
}

output "public_ip" {
  description = "Public IP of the developer VM"
  value       = aws_instance.dev_vm.public_ip
}

output "private_ip" {
  description = "Private IP of the developer VM"
  value       = aws_instance.dev_vm.private_ip
}

output "key_name" {
  description = "Key pair name used for the instance"
  value       = aws_key_pair.dev_key.key_name
}
