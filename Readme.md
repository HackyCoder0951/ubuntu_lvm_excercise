
# 🧠 LVM Thin Provisioning with Auto Expansion on Ubuntu

This project provides a modular, production-ready setup to manage **large, dynamically growing storage** using LVM Thin Provisioning on Ubuntu. It enables you to start with minimal storage and expand on-the-fly by detecting and integrating new disks.

---

## 📌 Features

- Thin-provisioned logical volume (100TB virtual size by default)
- Automatically detects and adds new physical disks
- Expands thin pool without downtime
- Cron and systemd support for automation
- Optional .deb packaging and GitHub Actions CI

---

## 🛠️ Scripts Included

### 1. `lvm_thinpool_initial_setup.sh`

📁 Path: `/usr/local/bin/lvm_thinpool_initial_setup.sh`

🔧 One-time setup script:
- Initializes first disk (e.g., `/dev/sdb`)
- Creates:
  - Volume Group: `vgthin`
  - Thin Pool: `thinpool`
  - Metadata LV: `thinmeta`
  - Thin-provisioned LV: `lvdata` (default: 100TB)
- Formats and mounts LV to `/data`
- Adds to `/etc/fstab`

📦 **Usage**:
```bash
sudo /usr/local/bin/lvm_thinpool_initial_setup.sh
```

---

### 2. `auto_detect_and_expand_thinpool.sh`

📁 Path: `/usr/local/bin/auto_detect_and_expand_thinpool.sh`

🔁 Auto-detect and integrate new raw disks:
- Partitions new unpartitioned disks
- Creates PVs
- Adds them to Volume Group `vgthin`
- Expands `thinpool` using free space

📦 **Usage**:
```bash
sudo /usr/local/bin/auto_detect_and_expand_thinpool.sh
```

📆 **Cron Automation**:
```bash
sudo crontab -e
# Add:
@hourly /usr/local/bin/auto_detect_and_expand_thinpool.sh
```

🪵 **Logs**:
```
/var/log/lvm_auto_expand.log
```

---

## 📂 Filesystem Overview

| Component                     | Purpose                                  |
|------------------------------|------------------------------------------|
| `/dev/vgthin/lvdata`         | Thin-provisioned Logical Volume           |
| `/data`                      | Mount point for LV                        |
| `/etc/fstab`                 | Ensures auto-mount on reboot              |
| `/var/log/lvm_auto_expand.log` | Log of expansion events                |

---

## 🔍 Monitoring Thin Pool Usage

Check thin pool usage:
```bash
sudo lvs -a
```

Detailed usage monitoring:
```bash
sudo lvs -o+seg_monitor,seg_size,data_percent,metadata_percent
```

> ⚠️ **Watch `data_percent` and `metadata_percent`**.  
> If either reaches 100%, I/O operations will fail.

---

## 📈 Disk Expansion Plan Example

| Time       | Action                        | VG Size | Thin Pool Size |
|------------|-------------------------------|---------|----------------|
| Month 0    | Initial setup (30GB disk)     | 30GB    | ~28GB          |
| Month 6    | Add 1x 4TB disk               | 4.03TB  | ~2TB           |
| Month 12   | Add 1x 4TB disk               | 8.03TB  | ~6TB           |
| Month 18   | Add 1x 4TB disk               | 12.03TB | ~10TB          |

---

## 🧪 Requirements

- Ubuntu 20.04 or newer
- Packages: `lvm2`, `parted`, `coreutils`, `cron`
- Root privileges
- Clean (unpartitioned) disks for auto-detection

---

## ⚠️ Best Practices

- Always maintain **5–10% free space** in the thin pool
- Set up alerts (email, Prometheus, etc.) for usage thresholds
- Monitor `data_percent` and `metadata_percent` regularly
- Avoid overcommitting disk without growth planning
- Always pre-test in staging or non-critical environments

---

## 🛠️ Optional Enhancements

### Systemd Service & Timer (Alternative to Cron)

Create service unit:
```bash
sudo nano /etc/systemd/system/lvm-expand.service
```

```ini
[Unit]
Description=Auto Expand LVM Thin Pool
After=multi-user.target

[Service]
ExecStart=/usr/local/bin/auto_detect_and_expand_thinpool.sh
```

Create timer unit:
```bash
sudo nano /etc/systemd/system/lvm-expand.timer
```

```ini
[Unit]
Description=Run LVM Expansion Hourly

[Timer]
OnBootSec=10min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
```

Enable and start the timer:
```bash
sudo systemctl daemon-reexec
sudo systemctl enable --now lvm-expand.timer
```

---

## 📦 Optional: `.deb` Package Structure

Project can be packaged for easier distribution:

```
my-lvm-expander/
├── DEBIAN
│   └── control
├── usr
│   └── local
│       └── bin
│           ├── lvm_thinpool_initial_setup.sh
│           └── auto_detect_and_expand_thinpool.sh
└── etc
    └── systemd
        └── system
            ├── lvm-expand.service
            └── lvm-expand.timer
```

Build the `.deb`:
```bash
dpkg-deb --build my-lvm-expander
```

---

## 🧪 GitHub Actions Test Workflow

Use this to lint and validate the shell scripts:

`.github/workflows/test.yml`:
```yaml
name: Test LVM Expansion Scripts

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Lint Shell Scripts
        uses: ludeeus/action-shellcheck@master

      - name: Ensure Scripts Are Executable
        run: |
          chmod +x ./lvm_thinpool_initial_setup.sh
          chmod +x ./auto_detect_and_expand_thinpool.sh
          echo "✅ Scripts are executable"
```

---

## 📜 License

MIT License — Free to use, modify, and distribute for personal and commercial use.

---

## 👨‍💻 Maintainer

Built and maintained by **[Your Name or Team]**  
Designed for scalable, cloud-ready Linux storage automation.