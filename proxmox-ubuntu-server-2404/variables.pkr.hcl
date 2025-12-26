variable "proxmox_url" {
  type    = string
  default = "<https://<IP or FQDN>>:8006/api2/json>"
}

variable "proxmox_username" {
  type    = string
  default = "<Your automation account name>"
}

variable "proxmox_token" {
  type    = string
  default = "<API Token>"
}

variable "proxmox_node" {
  type    = string
  default = "<Proxmox Node name>"
}

variable "proxmox_storage_pool" {
  type    = string
  default = "<Storage pool name for the VM/Templates>"
}

variable "proxmox_iso_storage_pool" {
  type    = string
  default = "<Storage pool for ISO files>"
}

variable "proxmox_vm_pool" {
  type    = string
  default = "<The name of the pool voor templates>"
}

variable "vm_id" {
  default = <VM ID>
}

variable "vm_boot_iso" {
  type    = string
  default = "<the path to the Ubuntu boot iso>"
}

variable "vm_description" {
  type    = string
  default = "<Build description>"
}

variable "vm_os" {
  type    = string
  default = "<OS Type, Windows or Linux>"
}

variable "vm_os_sku" {
  type    = string
  default = "<Server or client>"
}

variable "vm_os_version" {
  type    = string
  default = "<Version number (2404, 2510 etc)>"
}

variable "build_version" {
  type    = string
  default = "<Your Build version>"
}