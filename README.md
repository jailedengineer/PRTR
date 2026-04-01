# PRTR — Paulo's Router

<p align="center">
  <img src="BSDRP/Files/boot/lua/brand-prtr.lua" alt="PRTR" width="400"/>
</p>

**PRTR** is a FreeBSD-based router distribution forked from [BSDRP](https://github.com/ocochard/BSDRP) (BSD Router Project by Olivier Cochard-Labbé), focused on:

- **BIRD 3.x** multithreading performance research at full DFZ scale
- **Post-Quantum Cryptography (PQC)** BGP session research using OpenSSL 3.6.1 + liboqs + oqs-provider
- **Production IX.br peering** — tested with ~60 BGP sessions and 3M+ routes

---

## Key Differences from BSDRP

| Feature | BSDRP | PRTR |
|---------|-------|------|
| Routing daemon | FRR / BIRD 2 | BIRD 3.x |
| TLS stack | OpenSSL (default) | OpenSSL 3.6.1 (PQC-capable) |
| PQC support | No | liboqs + oqs-provider |
| Metrics | — | prometheus-bird-exporter + node_exporter |

---

## Hardware Tested

| Platform | CPU | Role |
|----------|-----|------|
| Dell VEP1485 | Intel Atom C3958 (Denverton) | Primary production router |
| Dell R630 | Intel Xeon E5-2673 v3 | IPFW bandwidth shaping |
| ServerU L800 | Intel Atom C2758 (Avoton) | Production router (legacy) |

---

## Production Results

BIRD 3.x with `threads 4` on VEP1485 (Denverton C3958):

- **3M+ routes** from full DFZ table
- **~60 BGP sessions** peering at IX.br (SP, RJ, CE, SC, BA, PR, RS, DF, PE)
- `birdc show protocols` response: **3.39 seconds** under full load
- OSPF `Full/DR` — no missed hellos

---

## Build Requirements

- FreeBSD host (16.0-CURRENT recommended)
- `poudriere` installed
- `git`, `xz` available
- ~20GB free disk space

---

## Quick Start

```sh
# Clone PRTR
git clone https://github.com/jailedengineer/PRTR.git
cd PRTR

# Build everything (packages + image + compressed artifacts + checksums)
make release
```

The first build takes 2-4 hours. Subsequent builds only rebuild changed packages.

### Build targets

```sh
make              # Build images (default)
make release      # Build + compress + checksum
make compress-images  # Compress existing images with xz
make checksum-images  # Generate sha256 checksums
make clean        # Clean images only
make clean-all    # Clean everything including packages and jail
make upstream-sync    # Fetch latest FreeBSD src + ports, update hashes
make help         # Show all targets
```

---

## Upgrade (Remote, No USB)

```sh
# Copy upgrade image to router
scp PRTR-2.1.1-dev-upgrade-amd64.img.xz root@router:/data/

# On router — upgrade to inactive partition
xzcat /data/PRTR-2.1.1-dev-upgrade-amd64.img.xz | upgrade

# Reboot into new version
reboot

# Rollback if needed
system rollback
```

---

## Release Artifacts

| File | Description |
|------|-------------|
| `PRTR-VERSION-full-amd64.img.xz` | Full firmware image for fresh install |
| `PRTR-VERSION-upgrade-amd64.img.xz` | Upgrade image (no USB required) |
| `PRTR-VERSION-amd64.mtree.xz` | Filesystem manifest |
| `PRTR-VERSION-debug-amd64.tar.xz` | Debug symbols |
| `*.sha256` | SHA256 checksums |

---

## Key Packages

| Port | Version | Purpose |
|------|---------|---------|
| `net/bird3` | 3.2.0 | BIRD routing daemon with multithreading + BMP |
| `security/openssl36` | 3.6.1 | PQC-capable OpenSSL |
| `security/liboqs` | 0.15.0 | Post-quantum algorithm library |
| `security/openssl-oqsprovider` | 0.11.0 | OQS provider for OpenSSL 3.6 |
| `net-mgmt/prometheus-bird-exporter` | 1.4.4 | Prometheus metrics for BIRD |
| `sysutils/node_exporter` | 1.9.1 | Prometheus host metrics |

---

## FreeBSD Source Base

PRTR 2.1.x is built from:

- **FreeBSD src**: commit `5b7aa6c7bc9` (16.0-CURRENT, March 13 2026)
- **FreeBSD ports**: tracked in `Makefile.vars`

To update to latest sources:

```sh
make upstream-sync
make release
```

---

## BIRD 3 Configuration Notes

```
# bird.conf — top level (not inside options {})
threads 4;    # Recommended for Denverton C3958

# BGP password — BIRD3 assumes MD5 by default
# Just use simple form:
password "secret";
```

Function return types must be explicit in BIRD3:

```
# BIRD2 style (warning in BIRD3)
function net_martian() { ... }

# BIRD3 style (correct)
function net_martian() -> bool { ... }
```

---

## Credits

- **Olivier Cochard-Labbé** — [BSDRP](https://github.com/ocochard/BSDRP) founder and maintainer
- **FreeBSD Project** — base operating system
- **CZ.NIC** — [BIRD](https://bird.network.cz/) routing daemon
- **Open Quantum Safe** — [liboqs](https://openquantumsafe.org/) and oqs-provider

---

## License

BSD 2-Clause License — see [LICENSE](LICENSE)

Copyright (c) 2009-2026, The BSDRP Development Team  
PRTR modifications Copyright (c) 2026, Paulo Fragoso / NLINK ISP

---

## Author

**Paulo Fragoso** — paulo@nlink.com.br  
Founder/Director of Engineering, NLINK ISP  
Founder/CTO, GMNET Telecomunicações  
Electronic Engineer & FreeBSD kernel contributor  
Recife, Brazil

FreeBSD kernel contributions: [D55607](https://reviews.freebsd.org/D55607), [D56029](https://reviews.freebsd.org/D56029), [D56050](https://reviews.freebsd.org/D56050) — hwpmc(4) fixes
