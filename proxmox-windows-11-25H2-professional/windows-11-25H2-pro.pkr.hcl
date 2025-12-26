# ---------------------------------------------------------------------------
# Packer configuration / Required_plugins block
# https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso
# https://github.com/rgl/packer-plugin-windows-update
# ---------------------------------------------------------------------------
packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.2"
    }

    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = ">= 0.14.0"
    }
  }
}

# ---------------------------------------------------------------------------
# SOURCE: Windows 11 25H2 Professional on Proxmox
# ---------------------------------------------------------------------------

locals {
  build_date = formatdate("YYYY-MM-DD", timestamp())
}

source "proxmox-iso" "windows_11_25H2_pro" {
  # -------------------------------------------------------------------------
  # Proxmox connection
  # -------------------------------------------------------------------------
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # -------------------------------------------------------------------------
  # Base Guest OS information
  # -------------------------------------------------------------------------
  vm_id = var.vm_id
  vm_name = join(
    "-",
    [
      "build",
      var.vm_os,
      var.vm_os_sku,
      var.vm_os_version,
      var.vm_os_edition,
      var.build_version
    ]
  )
  template_name = join(
    "-",
    [
      "template",
      var.vm_os,
      var.vm_os_sku,
      var.vm_os_version,
      var.vm_os_edition,
      var.build_version
    ]
  )
  template_description = var.vm_description
  os                   = "win11"
  machine              = "q35"
  memory               = 8192
  cores                = 4
  sockets              = 1
  cpu_type             = "x86-64-v2-AES"
  qemu_agent           = true
  task_timeout         = "10m"
  tags = join(";", [
    "os_${var.vm_os}",
    "os_sku_${var.vm_os_sku}",
    "os_ver_${var.vm_os_version}",
    "os_edition_${var.vm_os_edition}",
    "build_version_${var.build_version}",
    "build_date_${local.build_date}"
  ])
  pool = var.proxmox_vm_pool

  # -------------------------------------------------------------------------
  # Firmware / UEFI (OVMF)
  # -------------------------------------------------------------------------
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # -------------------------------------------------------------------------
  # TPM (For Windows 11)
  # -------------------------------------------------------------------------
    tpm_config {
    # Storage where Proxmox stores the TPM state (tpmstate0)
    tpm_storage_pool = var.proxmox_storage_pool

    # "v2.0" (default) of "v1.2"
    tpm_version = "v2.0"
  }

  # -------------------------------------------------------------------------
  # Boot configuration
  # -------------------------------------------------------------------------
  boot      = "order=virtio0;ide0"
  boot_wait = "5s"
  boot_command = [
    "<enter><enter>"
  ]


  # -------------------------------------------------------------------------
  # Primary Disk configuration
  # -------------------------------------------------------------------------
  scsi_controller = "virtio-scsi-single"
  disks {
    type         = "virtio"
    storage_pool = var.proxmox_storage_pool
    disk_size    = "80G"
    cache_mode   = "writeback"
    discard      = true
    io_thread    = true
  }

  # -------------------------------------------------------------------------
  # Bootable ISO
  # -------------------------------------------------------------------------
  boot_iso {
    type         = "ide"
    iso_file     = var.vm_boot_iso
    iso_checksum = "none"
    unmount      = true
  }

  # -------------------------------------------------------------------------
  # Autounattend.xml
  # -------------------------------------------------------------------------
  # This is what drives Windows autoinstall.
  additional_iso_files {
    type              = "ide"
    index             = 1
    iso_storage_pool  = var.proxmox_iso_storage_pool
    unmount           = true
    keep_cdrom_device = false
    cd_files = [
      "./scripts/pre-build/*"
    ]
    cd_label = "cidata"
  }

  additional_iso_files {
    type         = "ide"
    index        = 2
    iso_file     = var.vm_virtio_iso
    iso_checksum = "none"
    unmount      = true
  }

  # -------------------------------------------------------------------------
  # Network configuration
  # -------------------------------------------------------------------------
  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = true
  }

  # -------------------------------------------------------------------------
  # Display
  # -------------------------------------------------------------------------
  vga {
    type = "qxl"
  }

  # -------------------------------------------------------------------------
  # WINRM / Communicator
  # -------------------------------------------------------------------------
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "P@ssw0rd!"
  winrm_timeout  = "12h"
  winrm_use_ssl  = true # Use WINRM over TLS
  winrm_insecure = true # Use a self-signed certificate

}

# ---------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------
build {
  name    = "windows_11_25H2_pro"
  sources = ["source.proxmox-iso.windows_11_25H2_pro"]

  # -------------------------------------------------------------------------
  # Windows Updates
  # -------------------------------------------------------------------------
  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
  
    filters = [
      "exclude:$_.Title -like '*Driver*'",
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ]
  
    update_limit = 50
  }

  # -------------------------------------------------------------------------
  # Upload the unattended file
  # -------------------------------------------------------------------------
  provisioner "file" {
    source      = "scripts/post-build/unattend/unattend.xml"
    destination = "C:\\Windows\\System32\\Sysprep\\unattend.xml"
  }

  # -------------------------------------------------------------------------
  # Create the scripts directory
  # -------------------------------------------------------------------------
  provisioner "powershell" {
    inline = [
      "if (-not (Test-Path 'C:\\Windows\\Setup\\Scripts')) { New-Item -Path 'C:\\Windows\\Setup\\Scripts' -ItemType Directory -Force | Out-Null }"
    ]
  }

  # -------------------------------------------------------------------------
  # Upload the SetupComplete.cmd file
  # -------------------------------------------------------------------------
  provisioner "file" {
    source      = "scripts/post-build/setupcomplete/SetupComplete.cmd"
    destination = "C:\\Windows\\Setup\\Scripts\\SetupComplete.cmd"
  }

  # -------------------------------------------------------------------------
  # Upload the postImage-winrm-reset.ps1 file
  # -------------------------------------------------------------------------
  provisioner "file" {
    source      = "scripts/post-build/setupcomplete/postImage-winrm-reset.ps1"
    destination = "C:\\Windows\\Setup\\Scripts\\postImage-winrm-reset.ps1"
  }

  # -------------------------------------------------------------------------
  # Upload the postoobecleanup.cmd file
  # -------------------------------------------------------------------------
  provisioner "file" {
    source      = "scripts/post-build/unattend/postoobecleanup.cmd"
    destination = "C:\\Windows\\Setup\\Scripts\\postoobecleanup.cmd"
  }

  # -------------------------------------------------------------------------
  # Cleanup image
  # -------------------------------------------------------------------------
  provisioner "powershell" {
    script = "scripts/post-build/cleanup-for-image.ps1"
  }

  # -------------------------------------------------------------------------
  # Final command
  # -------------------------------------------------------------------------
  provisioner "powershell" {
    inline = [
      "Write-Host 'Running sysprep and shutting down...'",
      "C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /quiet /shutdown"
    ]
  }
}