### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
#### Debian or Ubuntu (and derivatives):
```
apt-get install build-essential m4 gawk bc bison flex texinfo python3 python perl libtool autoconf automake autopoint gperf bsdtar libarchive-dev xorriso wget git mtools liblzma-dev pigz libgmp-dev libmpfr-dev libmpc-dev pixz libelf-dev libssl-dev zlib1g-dev
```
#### Fedora (and derivatives):
```
dnf install libarchive-devel libarchive bsdtar autoconf automake git autoconf automake gawk m4 bison flex texinfo patchutils gcc gcc-c++ libtool gettext-devel xorriso glibc-static perl python3 python2 xz-devel mtools pigz gmp-devel mpfr-devel libmpc-devel pixz openssl-devel elfutils-devel zlib-devel xz-devel wget
```
#### Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools git pigz python python2 pixz
```
#### Void Linux
```
xbps-install -S base-devel libarchive-devel xorriso mtools git patch pigz python3 python pixz zlib-devel liblzma-devel zstd
```
  In Void Linux you may have to:
```
ln -s /bin/x86_64-linux-musl-gcc /bin/x86_64-linux-musl-cc
```
#### Ataraxia Linux:
```
prt-get depinst libisoburn python python2 mtools pixz
```

### Compiling pkgutils
Ataraxia Linux uses pkgutils as its package manager. We've modified it for features support that we need. You should do this commands to install pkgutils (**AS ROOT**):
```
cd /tmp
git clone https://github.com/protonesso/pkgutils.git --depth 1
cd pkgutils
make -f Makefile.dynamic
make install
```

### Building
We have seperated the build process into seperate "stages":
```
 * 0          - This stage intended to compile cross-toolchain
 * 1          - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)
 * 1a         - Resume stage 1, if you encounter a failure 
 * 1-embedded - This stage intended to compile small embedded system with cross-compiler (You don't need to compile stage 0)
 * 2          - This stage is intended to generate .iso and stage images
 * 2-hdd      - This stage is intended to generate hard disk image. Support for reiser4 is required.
 * 2-stage    - This stage is intended to generate .iso with stage filesystem in initramfs
 * 2-embedded - This stage is intended to generate hard disk and stage images for embedded devices
 * all        - Performs stages 0, 1 and 2 automatically

```
To begin the build process, **as root**:
```
BARCH=[supported architecture] ./build stage [stage number]
```
See [supported platforms and architecures.](platforms.md)
And magic happens!
