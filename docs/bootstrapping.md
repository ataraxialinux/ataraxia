### Installing build dependencies
We need specific packages to build this Linux distribution. Without them you can't perform the required tasks. To install required build dependencies:
#### Fedora
```
dnf groupinstall "Development Tools" "C Development Tools and Libraries"
dnf install clang libcxx-devel glibc-static libcxx-static libunwind-devel jq zstd bsdcpio bsdtar curl mtools libisoburn which python3 texinfo meson freetype-devel zlib-devel xz-devel libzstd-devel libarchive-devel elfutils-libelf-devel openssl-devel readline-devel libffi-devel sqlite-devel
```
#### Ataraxia Linux:
```
tsukuri emerge libisoburn mtools freetype
```

### Compiling package manager
Ataraxia Linux uses `tsukuri` as its package manager. You should do this commands to install `tsukuri` (**AS ROOT**):
```
cd /tmp
git clone https://github.com/ataraxialinux/tsukuri.git --depth 1
cd tsukuri
mkdir build
cd build
meson --prefix=/usr -Dsystemd=false ../
ninja
ninja install
```

### Building
Arguments supported by "build script":
```
target		- Select target for build
```
Sub-arguments supported by "build script":
```
 -a <Architecture>		- Select architecture for build
```
We have seperated the build process into seperate "targets":
```
 * toolchain              - This stage intended to compile cross-toolchain
 * system                 - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)
```
To begin the bootstrap process, **as root**:
See [supported platforms and architecures.](platforms.md)
```
./build target -a [supported architecture] [target name]
```
And magic happens!
