#----------------------------------------------------------------------------------------------------
# outputs.tf
# author: Kabera Clapton
#
# description: Store the outputs produced by the creation of the resources
#---------------------------------------------------------------------------------------------------- 

output "public_dns" {
  value = aws_instance.sandbox_server.public_dns
}

output "ssh_user" {
 value = aws
}

output "key_name" {
  value = aws_key_pair.admin_key.key_name
}

output "key_path" {

}

output "public_ip" {
  value = aws_instance.sandbox_server.public_ip
}
