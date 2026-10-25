# x86_64 QEMU / OVMF Secure Boot lab — custom PK, KEK, db

A Linux-hosted, rootless QEMU test setup for booting **signed x86_64 UEFI EFI/PE executables** or an existing UEFI disk/ISO with **your own Secure Boot trust anchors**.

Unlike firmware pre-enrolled with Microsoft keys, the default uses a **blank variable store**. It can be configured by clicking through the OVMF/UEFI firmware menu or, optionally, preconfigured from the command line with `virt-fw-vars`.

> **Two distinct states:** OVMF is *Secure Boot capable* immediately; Secure Boot *enforcement* (UEFI `SecureBoot=1`, `SetupMode=0`) begins only **after the PK, KEK and db have been enrolled**, Secure Boot has been enabled, and you have left Custom Mode as appropriate. If you prefer booting straight into enforcement mode, use **offline enrollment** (below).

## NixOS quick start (recommended)

This project includes **`flake.nix`** and **`shell.nix`** so you do not need
`apt` or system-wide QEMU/OVMF installation. They both request a custom
x86_64 OVMF derivation with `secureBoot = true`, `fdSize4MB = true` and
`msVarsTemplate = false`, and export the resulting **exact Nix store paths**:

```sh
export OVMF_CODE=/nix/store/.../FV/OVMF_CODE.fd
export OVMF_VARS_TEMPLATE=/nix/store/.../FV/OVMF_VARS.fd
```

You do not have to set those paths manually. From the extracted project
folder, use **one** of the following:

```bash
nix develop         # flakes enabled; uses nixpkgs/nixos-26.05
# OR:
nix-shell           # classic Nix channel; uses your <nixpkgs>
```

For Nix installations where flakes are disabled by default, use:

```bash
nix --extra-experimental-features 'nix-command flakes' develop
```

The shell supplies `qemu-system-x86_64`, `openssl`, `sbsign` and
`virt-fw-vars`; the **QEMU/OVMF build** and both **manual and offline
PK/KEK/db enrollment** work without modifying your host UEFI variables.
Your staged public certificates and writable NVRAM live locally under `work/`.
The initial Nix build may have to compile OVMF if the variant is not cached.

```bash
./sb-lab init --pk /path/PK.cer --kek /path/KEK.cer --db /path/DB.cer
./sb-lab boot                     # enroll in OVMF menu
# or, instead of manual enrollment (do not run while VM is booted):
./sb-lab enroll-offline
./sb-lab status

./sb-lab boot --efi /path/signed.efi
# OR: ./sb-lab boot --disk /path/uefi-disk.img
```

**Important:** use the *same* version of OVMF to reuse a saved
`work/OVMF_VARS.fd`, or reset the variables if you switch to an incompatible
firmware build. The NVRAM file survives between QEMU launches but not
`./sb-lab reset --yes`. Avoid passing the host's real EFI variables into
this test VM. The Nix shell targets an **x86_64-linux host**.

If you want KVM acceleration, your account must have access to `/dev/kvm`.
The launcher falls back automatically to software emulation; alternatively,
add your user to NixOS's `kvm` group with your system configuration,
then log out and back in. This is optional for functional testing.

## Requirements

Linux with a local graphical session for the firmware configuration interface:

- `qemu-system-x86_64`, `ovmf`, `openssl`
- Optional: `virt-fw-vars` (`virt-firmware` / `python3-virt-firmware`) for offline enrollment or host-side inspection
- Optional: `sbsign` (`sbsigntool`) for signing the EFI binary

Debian/Ubuntu:

```bash
sudo apt update
sudo apt install qemu-system-x86 ovmf openssl
sudo apt install python3-virt-firmware sbsigntool  # optional; distro package availability may vary
```

Fedora: typically `qemu-system-x86-core edk2-ovmf openssl virt-firmware sbsigntools`.
Arch: typically `qemu-desktop edk2-ovmf openssl virt-firmware sbsigntools`.

The script auto-detects the usual Debian/Ubuntu, Fedora, and Arch **x64 Secure Boot-capable** OVMF pairs. Use the full 4 MiB variant where available. If yours is elsewhere, set both `OVMF_CODE` and `OVMF_VARS_TEMPLATE` (example below).

## Option 1: Enroll keys yourself inside UEFI Setup (recommended for BIOS UI testing)

The `.pem`, `.crt`, `.der`, or `.cer` inputs must contain a **single X.509 certificate**, not a private key. The script will convert them to DER `.cer`, which OVMF can select in its file browser.

```bash
# 1. Initialize an empty, persistent NVRAM store and stage public certificates.
./sb-lab init \
  --pk /absolute/path/PK.pem \
  --kek /absolute/path/KEK.pem \
  --db /absolute/path/db.pem

# Optional: add more db certificates (repeating --db), or blacklist
# a certificate with --dbx /path/to/revoked.cer.

# 2. Start QEMU without a bootloader so you can enter UEFI setup.
./sb-lab boot
```

In the QEMU window, enter UEFI setup (usually **Esc** during startup; if it opens the shell, type `exit`). Firmware wording may vary with edk2 version. Navigate approximately:

1. **Device Manager → Secure Boot Configuration**.
2. Set **Secure Boot Mode → Custom Mode**.
3. Open **Custom Secure Boot Options → DB Options** and **Enroll Signature Using File**. Select `FS0:\KEYS\DB.cer` in the file picker (it may be a different `FSn:` device).
4. Import any additional `DB_02.cer`, etc., and any `DBX_01.cer` entries if required.
5. **KEK Options → Enroll** using `FSn:\KEYS\KEK.cer`.
6. **PK Options → Enroll** using `FSn:\KEYS\PK.cer` **last**. This moves firmware out of Setup Mode; once a PK is installed, subsequent key management is constrained.
7. Verify Secure Boot is **Enabled/Active**, leave Custom Mode (switch back to Standard Mode when appropriate), save and reset. Verify **SecureBoot=1** and **SetupMode=0**; installing a PK alone doesn't guarantee enforcement if the enable toggle is off.

UEFI menu labels can differ by OVMF build. Do **not** use a pre-enrolled `OVMF_VARS_4M.ms.fd` for this workflow; it may already trust other signatures.

Your enrollments persist in `work/OVMF_VARS.fd` across QEMU restarts.

To boot your signed EFI/PE binary **after** enabling Secure Boot:

```bash
./sb-lab boot --efi /path/to/signed-bootx64.efi
```

The script puts the executable at `work/esp/EFI/BOOT/BOOTX64.EFI`. QEMU presents `work/esp` as a **guest-writable virtual FAT disk** (`fat:rw:`) because QEMU IDE disks cannot use a read-only vvfat backend. No external FAT image authoring or root mounting is required. **Do not change files under `work/esp` on the host while QEMU is running**, and shut down the guest before modifying its staged files. This is ideal for fast `*.efi` iteration; you can replace the EFI executable on each invocation.

To test an existing bootable UEFI disk image or ISO instead:

```bash
./sb-lab boot --disk /path/to/uefi-boot-disk.img   # raw or .qcow2
./sb-lab boot --iso /path/to/uefi-image.iso
```

For disk/ISO mode the key-media disk remains attached as a second device for GUI key enrollment, but any previously staged `BOOTX64.EFI` is removed to avoid unintentionally booting it. The original disk image is protected by a **temporary snapshot overlay** (`snapshot=on`) so guest writes do not mutate the test input. For a persistent writable OS VM disk, remove `snapshot=on` in `sb-lab`.

## Option 2: Pre-enroll PK, KEK and db into the OVMF variable-store image

With `virt-fw-vars` installed, there is no need to navigate the UEFI menus. Stage your certificates as above, then run:

```bash
./sb-lab init --pk PK.pem --kek KEK.pem --db db.pem
./sb-lab enroll-offline
./sb-lab status
./sb-lab boot --efi signed.efi
```

**Result:** a persistent `work/OVMF_VARS.fd` with your PK, KEK, and db enrolled, and Secure Boot requested **on**. This is the requested persistent UEFI firmware **variable-store image**; its read-only companion firmware executable comes from your installed `ovmf` package. The command deliberately uses a **fresh blank** VARS template to avoid inheriting distro/Microsoft keys. It backs up the previous variables to `work/OVMF_VARS.fd.before-offline-enrollment.bak` and refuses to overwrite that backup.

If using multiple allowed signing certificates, repeat `--db` at the staging step. The defaults do **not** enroll Microsoft keys or other CAs. Certificates have the same test owner GUID (set `SB_LAB_OWNER_GUID` to change it). The enrolled cert public keys are stored in the firmware image; **private signing keys are never copied into the VM**.

## Verify Secure Boot, test rejection, and understand the trust chain

For **positive** testing, the bootloader's PE/COFF signature must validate under the public certificate (or appropriate CA) enrolled in **db**. A PK or KEK certificate by itself does **not** authorize execution. The PK controls key ownership, KEK controls updates to signature databases, db controls accepted EFI signatures, and dbx controls revoked signatures/hashes.

If your EFI application is not yet signed, this helper signs it with `sbsign` and your db signing key and certificate:

```bash
./sb-lab sign --efi unsigned.efi --key db.key --cert db.pem --out signed.efi
./sb-lab boot --efi signed.efi
```

For **negative** testing, boot the original unsigned binary using the same trusted NVRAM:

```bash
./sb-lab boot --efi unsigned.efi
```

With `SecureBoot=1` and no matching signature in `db` (and no other trusted signer), firmware should reject it (often with `Security Violation`). An EFI executable successfully booting while still in Setup Mode **does not** prove its signature was accepted.

On the host, `./sb-lab status` uses `virt-fw-vars` when installed. In a Linux guest booted with EFI runtime services, `mokutil --sb-state` and `efi-readvar -v PK`, `efi-readvar -v KEK`, `efi-readvar -v db` can provide additional checks.

## Reset / re-enroll / firmware overrides

```bash
./sb-lab reset --yes   # discard enrolled NVRAM, return to Setup Mode
./sb-lab boot          # keys are still staged for manual enrollment
```

If you stage a different certificate later via `./sb-lab keys ...`, this **does not automatically replace** the keys enrolled in existing NVRAM. Either reconfigure them properly through the firmware UI or reset and re-enroll. Offline enrollment always starts from a blank template (and creates a backup).

Override nonstandard OVMF firmware file locations:

```bash
export OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
export OVMF_VARS_TEMPLATE=/usr/share/OVMF/OVMF_VARS_4M.fd
./sb-lab init
./sb-lab boot
```

The virtual FAT drive uses `fat:rw:` rather than `fat:` to avoid QEMU's `Block node is read-only` error with IDE disks. This is separate from the persistent, writable OVMF VARS drive. For performance, QEMU uses KVM if `/dev/kvm` is accessible, otherwise TCG emulation. Force emulation with `./sb-lab boot --no-kvm`. This setup uses `-machine q35,smm=on`, protected `pflash` emulation, a read-only OVMF CODE image, and a writable, persistent OVMF VARS image.

## Security notes and scope

- Use **test certificates and images** in this environment. Host-side manipulation of the VM's NVRAM file can bypass its protections; this is **not** a physical root-of-trust, and it is not suitable for attestation of hostile VM operators.
- This setup tests **x86_64** UEFI Secure Boot. `*.efi` files must be UEFI PE/COFF executables and appropriately signed, not simply renamed Linux kernels or arbitrary file formats.
- A `.auth` (authenticated variable update), `.esl` (EFI signature list), or a private key is **not** an X.509 certificate. The staging helper intentionally accepts only one PEM/DER X.509 cert per input. If you already have `.esl` or `.auth` files, OVMF may support them through other enrollment paths; this utility's conversion is not suitable for those formats.
- FAT folder-drive mode is for **file-level EFI tests**. If you need a genuine partitioned raw GPT/ESP disk for storage/partition boot chain behavior, pass it using `--disk` instead.
- Different OVMF builds have different setup menus and may configure `SecureBootEnable` differently. **Always verify SecureBoot=1** before interpreting a pass/fail result.

## References

- [TianoCore/edk2 OVMF README](https://github.com/tianocore/edk2/blob/master/OvmfPkg/README) — Secure Boot + SMM requirements and enrollment options
- [Debian OVMF firmware variants](https://sources.debian.org/src/edk2/2022.11-6%2Bdeb12u2/debian/ovmf.README.Debian) — blank 4M VARS and secureboot CODE versus Microsoft-enrolled images
- [virt-fw-vars CLI reference](https://man.archlinux.org/man/extra/virt-firmware/virt-fw-vars.1.en) — PK/KEK/db enrollment into a pflash variable-store image
- [Debian Secure Boot in QEMU](https://wiki.debian.org/SecureBoot/VirtualMachine) — pflash, Q35, SMM, and QEMU boot options
