# WinPE Disk Drivers (VirtIO)

This directory is used during the **Windows PE** phase of Setup.

Windows Setup will scan the `$WinpeDriver$` folder for drivers very early in the installation process.  
The `disk` folder is specifically meant for **storage / disk controller drivers**, so Windows can:

- detect the virtual disk
- create partitions
- apply the Windows image to disk

## What to place here

Copy the required **VirtIO storage drivers** into this directory.

Typical examples include drivers for:

- VirtIO SCSI
- VirtIO Block

> If Windows Setup cannot see the disk, you are missing the correct storage driver here.

## Notes

- Keep the folder structure simple.
- You can copy the relevant driver folder(s) directly from the VirtIO ISO.
- Drivers should include the `.inf`, `.sys`, and `.cat` files.

