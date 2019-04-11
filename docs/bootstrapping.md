### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
Debian or Ubuntu (and derivatives):
```
apt-get install build-essential m4 wget gawk bc bison flex texinfo python3 python perl libtool autoconf automake autopoint gperf bsdtar libarchive-dev xorriso curl git mtools liblzma-dev pigz libgmp-dev libmpfr-dev libmpc-dev pixz libelf-dev libssl-dev groff
```
Fedora (and derivatives):
```
dnf install libarchive-devel libarchive bsdtar autoconf automake git autoconf automake gawk m4 bison flex texinfo patchutils gcc gcc-c++ libtool gettext-devel xorriso glibc-static perl python3 python2 xz-devel mtools pigz gmp-devel mpfr-devel libmpc-devel pixz openssl-devel elfutils-devel groff
```
Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools git pigz python python2 pixz
```
Ataraxia Linux:
```
prt-get depinst libisoburn python python2 mtools pixz
```

### Building
We have seperated the build process into seperate "stages":
```
 * 0          - This stage intended to compile cross-toolchain
 * 1          - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)
 * 1a         - Resume stage 1, if you encounter a failure 
 * 1-embedded - This stage intended to compile small embedded system with cross-compiler (You don't need to compile stage 0)
 * 2          - This stage is intended to generate .iso, hard disk and stage images
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
