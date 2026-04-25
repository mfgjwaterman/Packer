# WinPE Network Drivers (VirtIO)

This directory is used during the **Windows PE** phase of Setup.

Windows Setup will scan the `$WinpeDriver$` folder for drivers early in the installation process.  
The `net` folder is specifically meant for **network drivers**, so Windows can:

- bring up networking during setup (if needed)
- ensure connectivity for early provisioning stages
- avoid post-install driver surprises

## What to place here

Copy the required **VirtIO network drivers** into this directory.

Typical examples include drivers for:

- VirtIO NIC (`NetKVM`)

## Notes

- If your build works without networking during setup, you may not strictly need these.
- Including them is still recommended to keep the image build predictable.
- Drivers should include the `.inf`, `.sys`, and `.cat` files.

