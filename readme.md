# mdm-bypass-macos

A hardened, self-contained Bash script that removes Automated Device Enrollment (DEP/MDM) enrollment hooks from a Mac by creating a local administrator account and blocking Apple's enrollment callbacks — run entirely from **macOS Recovery**.

> **Use case:** refurbishers, IT admins re-provisioning decommissioned hardware, labs, and authorized device administration.

---

## ⚠️ Disclaimer

This tool is intended for **authorized device administration only** — devices you own, or are explicitly authorized to manage (e.g., refurbished units, decommissioned corporate hardware, lab machines).

It is **not** a tool for circumventing ownership of devices you don't control, and it does not bypass Activation Lock (Find My). Use responsibly and in accordance with your local laws and organizational policies.

---

## What it does

1. **Detects and mounts** the macOS System and Data volumes (APFS role-based detection with mounted-volume fallback).
2. **Creates a local administrator account** directly in the Data volume's Directory Services node (`dslocal`), selecting an available UID (501–599), generating a home directory, and granting admin group membership.
3. **Blocks Apple's MDM enrollment domains** in `/etc/hosts` by routing them to `0.0.0.0` (with automatic backup of the original file).
4. **Clears cloud enrollment records** and marks Setup Assistant as complete (`.AppleSetupDone`, cloudConfig markers).

After rebooting, the Mac boots directly to the login screen with your local admin account — bypassing the MDM / Remote Management enrollment prompt.

---

## Requirements

- **macOS Recovery mode**:
  - **Apple Silicon (M1/M2/M3/M4)**: Turn off the Mac, then press and hold the Power button until you see *Loading startup options*. Select *Options* → *Continue*.
  - **Intel**: Restart and immediately hold `Cmd + R` until the Apple logo appears.
- macOS must already be installed on the drive.
- Open **Terminal** from the top menu bar (**Utilities** → **Terminal**).
- Terminal in Recovery automatically runs as `root`.

> [!NOTE]
> Tested on macOS Monterey through Sequoia.

---

## Quick Start (One-Liner)

From the Recovery Terminal, run:

```bash
curl -fsSL https://raw.githubusercontent.com/HBL-LL/mdm-bypass-macos/main/mdm-bypass.sh -o mdm-bypass.sh && chmod +x mdm-bypass.sh && ./mdm-bypass.sh -y && reboot
```

This will download the script, create a local admin with default credentials (`Apple` / `1234`), block enrollment endpoints, and reboot into macOS.

---

## Usage

Download or clone the script, then execute from the Recovery terminal:

```bash
# Default interactive mode (user: Apple / password: 1234, with confirmation prompt)
./mdm-bypass.sh

# Fully unattended — skips confirmation prompt
./mdm-bypass.sh -y

# Custom administrator credentials
./mdm-bypass.sh -y -u techadmin -f "Tech Admin" -p 'Str0ngPass!'

# Block custom or enterprise MDM domains (comma-separated)
./mdm-bypass.sh -y -d "mdm.company.com,jamfcloud.com"
```

### Command-Line Flags

| Flag | Description | Default |
|:----:|-------------|---------|
| `-u` | Local admin username | `Apple` |
| `-f` | Full name / display name | `Apple` |
| `-p` | Password (minimum 4 characters) | `1234` |
| `-d` | Extra domains to block (comma-separated) | *(none)* |
| `-y` | Non-interactive mode (skip `y/N` confirmation) | `false` |
| `-h` | Display help and usage information | — |

---

## Built-in Blocked Domains

The script automatically appends null routes (`0.0.0.0`) in `/etc/hosts` for the following Apple enrollment endpoints:

| Domain | Purpose |
|--------|---------|
| `deviceenrollment.apple.com` | Apple Device Enrollment Program (DEP) endpoint |
| `mdmenrollment.apple.com` | Mobile Device Management enrollment server |
| `iprofiles.apple.com` | Configuration profile delivery service |
| `vpp.itunes.apple.com` | Volume Purchase Program (VPP) service |
| `mdm.apple.com` | General Apple MDM communication |

You can specify additional vendor-specific endpoints using the `-d` flag:
```bash
./mdm-bypass.sh -y -d "mdm.yourcompany.com,enroll.jamf.com"
```

---

## Safety & Design Notes

- **Idempotent** — safe to re-run; duplicate `/etc/hosts` entries are ignored, and existing usernames auto-increment (`Apple` → `Apple1`…).
- **Hosts Backup** — creates `/etc/hosts.bak-mdm` before modifying `/etc/hosts`. Restore anytime:
  ```bash
  sudo cp /etc/hosts.bak-mdm /etc/hosts
  ```
- **Dynamic UID Allocation** — scans for the first free UID in the range `501–599` instead of assuming 501 is vacant.
- **Fail-Fast Execution** — critical operations (Directory Services node access, record creation, password setting) abort immediately on failure with descriptive errors.
- **Clean Permissions** — creates and properly chowns (`$UID:20`) the user home folder in `/Volumes/<Data>/Users/<username>`.
- **Exit Status** — returns code `0` on success and `1` on failure, enabling safe shell chaining (`./mdm-bypass.sh -y && reboot`).

---

## Undoing the Bypass

To restore the device to its previous state or re-enroll in MDM:

1. **Restore hosts file**:
   ```bash
   sudo cp /etc/hosts.bak-mdm /etc/hosts
   ```
2. **Remove the created local user**:
   ```bash
   sudo dscl . -delete /Users/username
   sudo rm -rf /Users/username
   ```
3. **Remove setup and configuration profile markers**:
   ```bash
   sudo rm -f /var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
   sudo rm -f /var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
   sudo rm -f /private/var/db/.AppleSetupDone
   ```
4. **Trigger MDM re-enrollment**:
   ```bash
   sudo profiles renew -type enrollment
   ```

---

## Troubleshooting

| Issue | Cause & Solution |
|-------|------------------|
| **"Must run as root"** | You are running the script outside of Recovery mode. Boot into macOS Recovery and launch Terminal from the Utilities menu. |
| **"Data volume not found"** | The Data volume may be encrypted with FileVault and locked. Open **Disk Utility** in Recovery, select your Data volume (e.g. `Macintosh HD - Data`), click **Mount**, and enter your disk encryption password. |
| **"Directory Services node missing"** | macOS is not installed on the selected target disk, or the disk layout is unmounted or corrupted. |
| **Login loop after reboot** | Log in once via the console or Setup Assistant, then log into the created admin account. |
| **MDM prompt reappears** | Verify the hosts file contains the blocked domains: `cat /etc/hosts`. If using third-party MDMs, identify their enrollment servers and pass them via `-d`. |

---

## FAQ

**Does this bypass Activation Lock / iCloud lock?**  
No. This tool only handles MDM / DEP enrollment profiles. It cannot bypass hardware-tied iCloud Activation Lock or Find My.

**Does this survive macOS updates?**  
The local administrator account persists across updates. Major macOS system upgrades may recreate system `/etc/hosts` and setup markers; if an MDM prompt reappears, simply re-run the script from Recovery mode.

**Why must this be run in Recovery mode?**  
The local Directory Services database (`dslocal`) on the Data volume cannot be modified directly while macOS is running due to System Integrity Protection (SIP) and active daemon locks. Recovery mode provides the necessary unconstrained access to write user records directly.

---

## Contributing

Pull requests and issues are welcome — especially macOS version compatibility reports and additional MDM vendor endpoints.

## License

[MIT](LICENSE) © [Hamza Boulila](https://github.com/Hamza-Boulila)
