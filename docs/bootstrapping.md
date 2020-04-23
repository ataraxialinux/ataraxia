### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
#### Debian or Ubuntu (and derivatives):
```
apt-get install build-essential m4 bison flex texinfo python3 python perl libtool autoconf automake autopoint gperf libarchive-tools xorriso curl git mtools pigz zstd rsync pkg-config liblzma-dev libgmp-dev libmpfr-dev libmpc-dev libelf-dev libssl-dev zlib1g-dev libarchive-dev libzstd-dev libfreetype6-dev libpopt-dev libacl1-dev libcap-dev libmagic-dev libdb-dev
```
#### Fedora/RHEL/CentOS
```
dnf groupinstall "Development Tools"
dnf install mtools libisoburn python3 pigz libarchive curl bsdtar glibc-static xorriso autoconf automake libtool freetype-devel zlib-devel xz-devel libzstd-devel libarchive-devel elfutils-libelf-devel openssl-devel libdb-devel popt-devel file-devel libacl-devel libcap-devel
ln -sf python3 /usr/bin/python
```
#### Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools git pigz python rsync freetype2
```
#### Ataraxia Linux:
```
neko emerge libisoburn python mtools freetype cpio
```

### Compiling package manager
Ataraxia Linux uses `neko` as its package manager. You should do this commands to install pkgutils (**AS ROOT**):
```
cd /tmp
git clone https://github.com/ataraxialinux/neko.git --depth 1
cd neko
autoreconf -vif
./configure --disable-libprotonesso
make
make install
```

### Building
Arguments supported by "build script":
```
stage		- Select stage for build
image		- Build image to deploy to hard drive or sdcard
installer	- Build installer image
archive		- Build stage archive
```
Sub-arguments supported by "build script":
```
 -a <Architecture>		- Select architecture for build
 -j <number of core>		- Specify number of cores/threads for build
 -g <Options for gcc>		- Specify options for GCC
 -l <Linux kernel package>	- Specify your custom Linux kernel package
 -E				- Enable build for embedded devices
```
We have seperated the build process into seperate "stages":
```
 * meta-toolchain         - This stage intended to compile cross-toolchain
 * core-image-minimal     - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)
```
To begin the bootstrap process, **as root**:
See [supported platforms and architecures.](platforms.md)
```
./build stage -a [supported architecture] [stage name]
```
After bootstrap you can build target images
```
./build [image|installer|archive] -a [supported architecture]
```
And magic happens!
