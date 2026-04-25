# Packer – Unattended Windows Builds for Hyper-v or Proxmox

Update: 25-04-2026, added configurations for Hyper-v installations.

Full guide, here: https://michaelwaterman.nl/2025/12/19/from-clickops-to-devops-building-secure-windows-images-with-packer-on-proxmox/

This repository contains all files needed for a **fully unattended Windows installation using Packer on Hyper-v or Proxmox**.  
The setup is designed around reproducibility, transparency, and a clean-source mindset.

The configurations in this repository support the following operating systems:

- hyperv-windows-11-25h2-enterprise
- hyperv-windows-server-2016-core
- hyperv-windows-server-2016-dekstop
- hyperv-windows-server-2019-core
- hyperv-windows-server-2019-dekstop
- hyperv-windows-server-2022-core
- hyperv-windows-server-2022-dekstop
- hyperv-windows-server-2025-core
- hyperv-windows-server-2025-dekstop
- proxmox-ubuntu-desktop-2404
- proxmox-ubuntu-server-2404
- proxmox-windows-11-25H2-professional
- proxmox-windows-server-2016-core  
- proxmox-windows-server-2016-desktop  
- proxmox-windows-server-2019-core  
- proxmox-windows-server-2019-desktop  
- proxmox-windows-server-2022-core  
- proxmox-windows-server-2022-desktop  
- proxmox-windows-server-2025-core  
- proxmox-windows-server-2025-desktop  

Each directory contains everything required to build a reusable Hyper-v or Proxmox template for the specified Windows version and edition.

---

## Prerequisites

Before starting, make sure you have:

- A working Hyper-v or Proxmox environment
- A Proxmox API user and token configured for automation (Proxmox only)
- Windows installation ISO(s) available
- VirtIO driver ISO available in Proxmox (Proxmox only)
- Packer installed on the system running the build
- Installed the latest Windows ADK on the build machine
- Set the path to oscdimg.exe file in the environement variables

---

## Getting started

To start a build, follow these steps:

1. Change directory to one of the build folders:
   `cd proxmox-windows-server-2025-core`
2. Initialize Packer and download required plugins:
   `packer init .`
3. Validate the configuration:
   `packer validate .`
4. Start the build:
   `packer build .`





