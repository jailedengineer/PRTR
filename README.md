# PRTR — PQC-Ready Telecommunications Router

```
  ____  ____  _______ ____
 |  _ \|  _ \|__   __|  _ \
 | |_) | |_) |  | |  | |_) |
 |  __/|    /   | |  |    /
 | |   | |\ \   | |  | |\ \
 | |   | | | |  | |  | | | | NLINK
 |_|   |_| |_|  |_|  |_| |_| 2.1.3-dev
```

**PRTR** is an open-source FreeBSD-based router distribution for critical telecommunications infrastructure, forked from [BSDRP](https://github.com/ocochard/BSDRP) (BSD Router Project by Olivier Cochard-Labbé).

*Open-source BGP routing platform with post-quantum cryptography for critical infrastructure.*

---

## Overview

PRTR addresses a strategic gap in telecommunications infrastructure: major router vendors (Cisco, Huawei, Juniper) have no published PQC roadmap for carrier-grade equipment, while quantum computers capable of breaking classical BGP session cryptography are projected within 10–15 years.

PRTR provides a production-proven, auditable, nationally-managed firmware alternative based on FreeBSD and BIRD 3.x, with a complete NIST-standardized post-quantum cryptography stack.

### Core capabilities

- **BIRD 3.x** multithreading at full DFZ (Default-Free Zone) scale — ~3M routes
- **Post-Quantum Cryptography** — OpenSSL 3.6.1 + liboqs + oqs-provider with NIST FIPS 203/204/205 algorithms (ML-KEM, ML-DSA, SLH-DSA)
- **Remote upgrade** — NanoBSD dual-partition: no USB, no long maintenance window
- **Tenant routing** — multiple isolated virtual routers on a single appliance via FreeBSD jails

---

## Key Differences from BSDRP

| Feature | BSDRP | PRTR |
|---------|-------|------|
| Routing daemon | FRR / BIRD 2 | BIRD 3.x |
| TLS stack | OpenSSL (default) | OpenSSL 3.6.1 (PQC-capable) |
| PQC support | No | liboqs + oqs-provider (NIST FIPS 203/204/205) |
| Metrics | — | prometheus-bird-exporter + node_exporter |
| Tenant routing | Basic | Enhanced jail management (`tenant` script) |

---

## Hardware Tested

| Platform | CPU | Role |
|----------|-----|------|
| Dell VEP4600 | Intel Xeon D-2187NT (Skylake-D) | PQC research platform |
| Dell VEP1485 | Intel Atom C3958 (Denverton) | Primary production router |
| Dell R630 | Intel Xeon E5-2673 v3 | IPFW bandwidth shaping |
| Lanner L800 | Intel Atom C2758 (Avoton) | Production router (legacy) |
| Lanner L400 | — | Production router (legacy) |
| PC Engines APU | AMD GX-412TC | Edge deployments |

---

## Production Results

BIRD 3.x with `threads 4` on VEP1485 (Denverton C3958):

- **3M+ routes** from full DFZ (Default-Free Zone) table
- **~60 BGP sessions** (IPv4 + IPv6) across multiple Brazilian Internet Exchanges
- `birdc show protocols` response: **3.39 seconds** under full load
- OSPF `Full/DR` — no missed hellos
- Memory: **~979MB** for full DFZ table

---

## PQC Stack

```
Application (iBGP sessions)
    └── TLS 1.3 with hybrid groups (X25519MLKEM768)
        └── oqs-provider 0.11.0
            └── liboqs 0.15.0
                ├── ML-KEM  (FIPS 203) — Key Encapsulation
                ├── ML-DSA  (FIPS 204) — Digital Signature
                └── SLH-DSA (FIPS 205) — Hash-based Signature
            └── OpenSSL 3.6.1
                └── FreeBSD 16.0-CURRENT (PRTR-AMD64 kernel)
```

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

The first build takes 2–4 hours. Subsequent builds only rebuild changed packages.

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

## Remote Upgrade (No USB)

```sh
# Copy upgrade image to router
scp PRTR-2.1.3-dev-upgrade-amd64.img.xz root@router:/data/

# On router — upgrade to inactive partition
xzcat /data/PRTR-2.1.3-dev-upgrade-amd64.img.xz | upgrade

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

- **FreeBSD src**: commit `5b7aa6c7bc9` (16.0-CURRENT, March 2026)
- **FreeBSD ports**: tracked in `Makefile.vars`

```sh
make upstream-sync
make release
```

---

## BIRD 3 Configuration Notes

```
# bird.conf — top level (not inside options {})
threads 4;    # Recommended for Denverton C3958

# BGP TCP MD5 — BIRD3 assumes MD5 by default
password "secret";
```

Function return types must be explicit in BIRD3:

```
# Correct BIRD3 syntax
function net_martian() -> bool { ... }
```

---

## Upstream Contributions

Bugs found during PRTR development and contributed upstream:

| Project | Contribution | Status |
|---------|-------------|--------|
| FreeBSD kernel | [D55607](https://reviews.freebsd.org/D55607) — hwpmc: fix amd_get_msr() RDPMC indexing | Committed |
| FreeBSD kernel | [D56029](https://reviews.freebsd.org/D56029) — hwpmc: improve diagnostic messages | Committed |
| FreeBSD kernel | [D56050](https://reviews.freebsd.org/D56050) — hwpmc.4: correct stale defaults | Committed |
| BSDRP | [PR #54](https://github.com/ocochard/BSDRP/pull/54) — Remove retired le(4) driver | Merged |
| BSDRP | [PR #55](https://github.com/ocochard/BSDRP/pull/55) — Fix DEBUG_PROPAGATE empty string | Merged |

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
Co-Founder/Director of Engineering, NLINK ISP  
Founder/CTO, GMNET Telecomunicações  
Electronic Engineer & FreeBSD kernel contributor  
Recife, Brazil · [LinkedIn](https://linkedin.com/in/jailedengineer) · [Substack](https://jailedengineer.substack.com)
