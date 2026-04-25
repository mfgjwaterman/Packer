variable "iso_url" {
  type    = string
  default = "E:/ISO/Microsoft/Windows Server/Windows Server 2025/Windows Server 2025 - EN-US - VL.iso"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "build_directory" {
  type    = string
  default = "D:/Build"
}

variable "output_directory" {
  type    = string
  default = "E:/VM Templates/"
}

variable "switch_name" {
  type    = string
  default = "External - Virtual Switch"
}

variable "vm_description" {
  type    = string
  default = "Windows Server 2025 Desktop template for Hyper-V"
}

variable "vm_os" {
  type    = string
  default = "windows"
}

variable "vm_os_sku" {
  type    = string
  default = "server"
}

variable "vm_os_version" {
  type    = string
  default = "2025"
}

variable "vm_os_edition" {
  type    = string
  default = "desktop"
}

variable "build_version" {
  type    = string
  default = "v1"
}

variable "winrm_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type      = string
  default   = "P@ssw0rd!"
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