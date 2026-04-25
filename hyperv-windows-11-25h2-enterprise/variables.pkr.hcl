variable "iso_url" {
  type    = string
  default = "E:/ISO/Microsoft/Windows Desktop/Windows 11/en-us_windows_11_business_editions_version_25h2_updated_jan_2026_x64_dvd_09c1e011.iso"
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
  default = "Windows 11 Enterprise 25H2 template for Hyper-V"
}

variable "vm_os" {
  type    = string
  default = "windows"
}

variable "vm_os_sku" {
  type    = string
  default = "11"
}

variable "vm_os_version" {
  type    = string
  default = "enterprise"
}

variable "vm_os_edition" {
  type    = string
  default = "25h2"
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