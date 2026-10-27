#---------------------------------------------------------------------------------------------------- 
# backend.tf
# author: Kabera Clapton
#
# description: Sets up the remote backend state for remotely tracking the state of the cofig.
#----------------------------------------------------------------------------------------------------  

terraform {
  backend "s3" {
    bucket       = "sandbox-remote-backend723354237"
    key          = "terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
