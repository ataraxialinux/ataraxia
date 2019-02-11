# januslinux - Fast and compact Linux distribution which uses musl libc.

## Introduction to the distribution
januslinux is a fast and compact [Linux](https://www.kernel.org/) distribution which uses [musl libc](http://www.musl-libc.org/) and [busybox](https://busybox.net/) userland tools. This distribution is made from scratch. Its goal is to be optimized and compact. It uses a package manager called "pkgutils" from [CRUX](https://crux.nu/). januslinux is oriented for general use, but it is designed for advanced Linux users. januslinux was compiled with a hardened toolchain for better security. januslinux is a rolling distribution, it allows you to get the latest software. Also, januslinux have pretty good hardware support.

## Introduction to the build system
[januslinux](https://januslinux.github.io/) is made from scratch that means every package, configuration files were written from scratch and controlled by januslinux Inc. and contributors. To build Linux distro we're made a build system called "Janus" in honor of the god of beginnings, gates, transitions, time, duality, doorways, passages, and endings. It's the main purpose to build and port packages easily.

## Supported platforms
januslinux is ported on many CPU architectures. There are about 8 of them:
```
 * x86_64       - for 64-bit x86 CPUs
 * x86          - for 32-bit x86 CPUs beggining at Intel Pentium Pro (i686)
 * arm64        - for 64-bit ARM CPUs
 * armv7l       - for 32-bit ARM CPUs beggining at ARMv7-a (hard-float)
 * armv6l       - for 32-bit ARM CPUs beggining at ARMv6-a (hard-float)
 * armv5tel     - for 32-bit ARM CPUs beggining at ARMv5 (soft-float)
 * ppc64le      - for 64-bit PowerPC CPUs (little-endian)
 * ppc64        - for 64-bit PowerPC CPUs (big-endian)
 * ppc          - for 32-bit PowerPC CPUs (big-endian)
 * riscv64      - for 64-bit RISC V CPUs
 * riscv32      - for 32-bit RISC V CPUs
 * sh4          - for 32-bit SuperH 4 CPUs
```
 
## Index of source packages
TODO

## Bootstrapping
To be written

## In chroot
To be written

## Conclusion
So this document describes januslinux build system, how to use it. Thanks for attention!
