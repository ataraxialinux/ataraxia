### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
#### Fedora
```
dnf groupinstall "Development Tools" "C Development Tools and Libraries"
dnf install glibc-static libstdc++-static jq bsdcpio bsdtar curl mtools libisoburn which python3 gcc-plugin-devel freetype-devel zlib-devel xz-devel libzstd-devel libarchive-devel elfutils-libelf-devel openssl-devel gmp-devel mpfr-devel libmpc-devel readline-devel libffi-devel sqlite-devel
```
#### Arch Linux (and derivatives):
```
pacman -S base-devel xorriso mtools jq python rsync freetype2
```
#### Ataraxia Linux:
```
tsukuri emerge libisoburn mtools freetype
```

### Compiling package manager
Ataraxia Linux uses `tsukuri` as its package manager. You should do this commands to install `tsukuri` (**AS ROOT**):
```
cd /tmp
git clone https://github.com/ataraxialinux/neko.git --depth 1
cd neko
autoreconf -vif
./configure
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
 -d <desktop environment>       - Specify your desktop environment (gnome, sway, xfce, mate, budgie)
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
./build [image|installer|live|archive] -a [supported architecture]
```
And magic happens!
