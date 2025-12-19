# Packer – Unattended Windows Builds for Proxmox

This repository contains all files needed for a **fully unattended Windows installation using Packer on Proxmox**.  
The setup is designed around reproducibility, transparency, and a clean-source mindset.

The configurations in this repository support the following operating systems:

- proxmox-windows-server-2016-core  
- proxmox-windows-server-2016-desktop  
- proxmox-windows-server-2019-core  
- proxmox-windows-server-2019-desktop  
- proxmox-windows-server-2022-core  
- proxmox-windows-server-2022-desktop  
- proxmox-windows-server-2025-core  
- proxmox-windows-server-2025-desktop  

Each directory contains everything required to build a reusable Proxmox template for the specified Windows version and edition.

---

## Prerequisites

Before starting, make sure you have:

- A working Proxmox environment
- A Proxmox API user and token configured for automation
- Windows installation ISO(s) available in Proxmox
- VirtIO driver ISO available in Proxmox
- Packer installed on the system running the build

---

## Getting started

To start a build, follow these steps:

1. Change directory to one of the build folders:
   ```bash
   cd proxmox-windows-server-2025-core
2. Initialize Packer and download required plugins:
   ```packer init .
3. Validate the configuration:
   ```packer validate .
4. Start the build:
   ```packer build .


