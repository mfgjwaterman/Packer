variable "iso_url" {
  type    = string
  default = "<Path to the ISO file>"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "build_directory" {
  type    = string
  default = "<Path where the VM will be build>"
}

variable "output_directory" {
  type    = string
  default = "<Path to the export destination of the VM>"
}

variable "switch_name" {
  type    = string
  default = "<Name of the virtual switch (Get-VMSwitch)>"
}

variable "vm_description" {
  type    = string
  default = "<Build description>"
}

variable "vm_os" {
  type    = string
  default = "<OS Type, Windows>"
}

variable "vm_os_sku" {
  type    = string
  default = "<Server or client>"
}

variable "vm_os_version" {
  type    = string
  default = "<Version number (2022, 2025 etc)>"
}

variable "vm_os_edition" {
  type    = string
  default = "<Desktop or Core>"
}

variable "build_version" {
  type    = string
  default = "<Your Build version>"
}

variable "winrm_username" {
  type    = string
  default = "<Installation Account Name>"
}

variable "winrm_password" {
  type      = string
  default   = "<Installation Account Password>"
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