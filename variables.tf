variable "common_tag" {
  type    = map(string)
  default = { app = "app-gw-transit" }
}

variable "instance_type" {
  type    = string
  default = "t2.nano"
}

variable "ssh_key_name" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-west-1"
}