# SSH Key Generation (Temporary Build Keys)

This directory is used to store **temporary SSH keys** that are required during the Packer build process (for example, to allow SSH access during installation and provisioning).

For security reasons, **private and public keys are not stored in this repository** and must be generated locally before running the build.

---

## Generate SSH Keys

From this directory, run the following command:

```bash
ssh-keygen -t ed25519 -f id_ed25519 -C "packer-build-key"
