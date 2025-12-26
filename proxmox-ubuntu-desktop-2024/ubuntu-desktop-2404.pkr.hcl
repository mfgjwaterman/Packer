# ---------------------------------------------------------------------------
# Packer configuration / Required_plugins block
# ---------------------------------------------------------------------------
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# SOURCE: Ubuntu 24.04 on Proxmox
# ---------------------------------------------------------------------------

locals {
  build_date = formatdate("YYYY-MM-DD", timestamp())
}

source "proxmox-iso" "ubuntu_2404_desktop" {
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
  vm_id                = var.vm_id
  vm_name = join(
    "-",
    [
      "build",
      var.vm_os,
      var.vm_os_sku,
      var.vm_os_version,
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
      var.build_version
    ]
  )
  template_description = var.vm_description
  os                   = "l26"
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
  # Boot configuration
  # -------------------------------------------------------------------------
  boot      = "order=virtio0;ide2;net0"
  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall quiet ds=nocloud",
    "<f10><wait>"
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
  # Cloud-init / NoCloud autoinstall (user-data + meta-data)
  # -------------------------------------------------------------------------
  # We use a separate NoCloud ISO (cidata) with user-data & meta-data.
  # This is what drives Ubuntu autoinstall.
  additional_iso_files {
    type              = "ide"
    index             = 1
    iso_storage_pool  = var.proxmox_iso_storage_pool
    unmount           = true
    keep_cdrom_device = false
    cd_files = [
      "./cloud-init/meta-data",
      "./cloud-init/user-data"
    ]
    cd_label = "cidata"
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
    type = "virtio"
  }

  # -------------------------------------------------------------------------
  # SSH / Communicator
  # -------------------------------------------------------------------------
  ssh_username = "superuser"
  # ssh_password           = "packer"
  ssh_private_key_file   = "packer-ssh/packer_ed25519"
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 300
  ssh_agent_auth         = false

  # -------------------------------------------------------------------------
  # Cloud init
  # -------------------------------------------------------------------------
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool
}

# ---------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------
build {
  name    = "ubuntu-2404-desktop"
  sources = ["source.proxmox-iso.ubuntu_2404_desktop"]

  # 1) Configure-script upload
  provisioner "file" {
    source      = "scripts/template-configure.sh"
    destination = "/tmp/template-configure.sh"
  }

  # 2) Configure-script execution, use --debug for verbose output
  provisioner "shell" {
    inline = [
      "echo '[provision] Running template configure...'",
      "sudo chmod +x /tmp/template-configure.sh",
      "sudo /tmp/template-configure.sh"
    ]
  }

  # 3) Cleanup-script upload
  provisioner "file" {
    source      = "scripts/template-cleanup.sh"
    destination = "/tmp/template-cleanup.sh"
  }

  # 4) Cleanup-script execution, use --debug for verbose output
  provisioner "shell" {
    inline = [
      "echo '[provision] Running template cleanup...'",
      "sudo chmod +x /tmp/template-cleanup.sh",
      "sudo /tmp/template-cleanup.sh"
    ]
  }
}

