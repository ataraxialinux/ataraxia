### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
#### Debian or Ubuntu (and derivatives):
```
apt-get install build-essential m4 gawk bc bison flex texinfo python3 perl libtool autoconf automake autopoint gperf bsdtar xorriso curl git mtools liblzma-dev pigz libgmp-dev libmpfr-dev libmpc-dev pixz libelf-dev libssl-dev zlib1g-dev
```
#### Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools git pigz python pixz
```
#### Void Linux
```
xbps-install -S base-devel xorriso mtools git patch pigz python3 pixz zlib-devel liblzma-devel zstd
```
#### Ataraxia Linux:
```
ne -E libisoburn python mtools pixz
```

### Compiling pkgutils
Ataraxia Linux uses kagami as its package manager. You should do this commands to install pkgutils (**AS ROOT**):
```
cd /tmp
git clone https://github.com/ataraxialinux/kagami.git --depth 1
cd kagami
./build.sh -B
./build.sh -I
```

### Building
Arguments supported by "build script":
```
 -s <Stage number>		- Select stage for build
 -a <Architecture>		- Select architecture for build
 -j <number of core>		- Specify number of cores/threads for build
 -g <Options for gcc>		- Specify options for GCC
 -l <Linux kernel package>	- Specify your custom Linux kernel package
 -E				- Enable build for embedded devices
 -S				- Build stage archive
 -L				- Build live/installer image
 -I				- Build image to deploy to hard drive or sdcard.
 -c				- Clean everything after build.
 -C				- Clean everything except toolchain.
```
We have seperated the build process into seperate "stages":
```
 * 0          - This stage intended to compile cross-toolchain
 * 1          - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)

```
To begin the bootstrap process, **as root**:
```
./build -s [stage number] -a [supported architecture]
```
See [supported platforms and architecures.](platforms.md)
After bootstrap you can build target images
```
./build [-SLI] -a [supported architecture]
```
And magic happens!
