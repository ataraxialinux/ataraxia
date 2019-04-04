# januslinux - Fast and compact Linux distribution which uses musl libc.

## Introduction to the distribution
januslinux is a fast and compact [Linux](https://www.kernel.org/) distribution which uses [musl libc](http://www.musl-libc.org/). This distribution is made from scratch. Its goal is to be optimized and compact. It uses own fork of package manager called "pkgutils" from [CRUX](https://crux.nu/). januslinux is oriented for general use, but it is designed for advanced Linux users. januslinux was compiled with a hardened toolchain for better security. januslinux is a rolling distribution, it allows you to get the latest software. Also, januslinux have pretty good hardware support.

## Introduction to the build system
[januslinux](https://januslinux.github.io/) is made from scratch that means every package, configuration files were written from scratch and controlled by januslinux Inc. and contributors. To build Linux distro we have made a build system called "Janus" in honor of the god of beginnings, gates, transitions, time, duality, doorways, passages, and endings. It's the main purpose to build and port packages easily.

## Supported platforms
januslinux is ported on many CPU architectures. There are about 14 of them:
```
 * x86_64       - for 64-bit x86 CPUs
 * i686         - for 32-bit x86 CPUs beggining at classic Intel Pentium Pro
 * aarch64      - for 64-bit ARM CPUs
 * armv7l       - for 32-bit ARM CPUs beggining at ARMv7-a (hard-float)
 * armv5tel     - for 32-bit ARM CPUs beggining at ARMv5 (soft-float)
 * mips64       - for 64-bit MIPS CPUs beggining at MIPS Release 1 (big-endian)
 * mips64el     - for 64-bit MIPS CPUs beggining at MIPS Release 1 (little-endian)
 * mips         - for 32-bit MIPS CPUs beggining at MIPS Release 1 (big-endian)
 * mipsel       - for 32-bit MIPS CPUs beggining at MIPS Release 1 (little-endian)
 * ppc64le      - for 64-bit PowerPC CPUs (little-endian)
 * ppc64        - for 64-bit PowerPC CPUs (big-endian)
 * ppc          - for 32-bit PowerPC CPUs (big-endian)
 * riscv64      - for 64-bit RISC V CPUs
 * riscv32      - for 32-bit RISC V CPUs
```
 
## Index of source packages
We have separated packages on groups to make build system cleaner. We have following repositories for packages:
```
 * bsp          - Packages for specific board support(eg. Linux kernels, bootloaders, misc. tools)
 * community    - Packages maintained by januslinux community. Not supported by core team
 * experimental - Unstable packages mostly for testing new features and adding new packages
 * packages     - Main packages collection for Linux distribution
 * toolchain    - Packages to build cross-toolchain [mostly required to build basic system]
```

## Bootstrapping

### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform required tasks. To install required build dependencies:
Debian or Ubuntu (and derivatives):
```
apt-get install build-essential m4 wget gawk bc bison flex texinfo python3 python perl libtool autoconf automake autopoint gperf bsdtar libarchive-dev xorriso curl git mtools liblzma-dev pigz libgmp-dev libmpfr-dev libmpc-dev pixz
```
Fedora (and derivatives):
```
dnf install libarchive-devel libarchive bsdtar autoconf automake git autoconf automake gawk m4 bison flex texinfo patchutils gcc gcc-c++ libtool gettext-devel xorriso glibc-static perl python3 python2 xz-devel mtools pigz gmp-devel mpfr-devel libmpc-devel pixz
```
Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools git pigz python python2 pixz
```
januslinux:
```
prt-get depinst xorriso python python2 mtools pixz
```

### Getting source code
We're using git as control system. You need git to download source code:
```
git clone https://github.com/januslinux/janus
```
If you want to switch to specific version:
```
git checkout [januslinux version]
```

### Building
As already mentioned we use build system called "janus" to build januslinux. We have several build sections called "stages":
```
 * 0          - This stage intended to compile cross-toolchain
 * 1          - This stage intended to compile basic target system with cross-compiler (you don't need to compile stage 0)
 * 1a         - If you have failure while building it you can always continue task
 * 1-embedded - This stage intended to compile small embedded system with cross-compiler (you don't need to compile stage 0)
 * 2          - This stage intended to generate .iso, hard disk and stage images
 * 2-embedded - This stage intended to generate hard disk and stage images for embedded devices
 * all        - Just do 0, 1 and 2 stages automatically

```
To run build process (as root):
```
BARCH=[supported architecture] ./build stage [stage number]
```
And magic happends!

## Conclusion
So this document describes januslinux build system, how to use it. Thanks for attention!
