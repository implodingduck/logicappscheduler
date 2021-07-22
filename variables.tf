variable "subscription_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "key" {
  type = string
}

variable "container_name" {
  type = string
}

variable "location" {
  type = string
  default = "East US"
}

variable "vnet_cidr" {
    type = string 
    default = "10.16.0.0/22"
}

variable "default_subnet_cidr" {
    type = string 
    default = "10.16.0.0/24"
}

variable "vm_subnet_cidr" {
    type = string
    default = "10.16.1.0/24"
}