variable "iso_url" {
  type    = string
  default = "<replace>"
}

variable "iso_checksum" {
  type    = string
  default = "<replace>"
}

variable "build_directory" {
  type    = string
  default = "<replace>"
}

variable "output_directory" {
  type    = string
  default = "<replace>"
}

variable "switch_name" {
  type    = string
  default = "<replace>"
}

variable "vm_description" {
  type    = string
  default = "<replace>"
}

variable "vm_os" {
  type    = string
  default = "windows"
}

variable "vm_os_sku" {
  type    = string
  default = "<replace>"
}

variable "vm_os_version" {
  type    = string
  default = "<replace>"
}

variable "vm_os_edition" {
  type    = string
  default = "<replace>"
}

variable "build_version" {
  type    = string
  default = "<replace>"
}

variable "winrm_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type      = string
  default   = "<replace>"
  sensitive = true
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cpus" {
  type    = number
  default = 4
}

variable "disk_size" {
  type    = number
  default = 81920
}