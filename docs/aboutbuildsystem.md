## Introduction to the build system
[Ataraxia Linux](https://github.com/ataraxialinux/ataraxia) is made from scratch. Every package build and configuration file was writen by and is controlled by the Ataraxia Linux team and it's contributors. To build the Linux distro, we have made a build system called "Ataraxia", which literally means "unperturbedness", "equanimity", and "tranquility". It's the main purpose to build and port packages easily.

### Getting source code
We're using git as control system. You need git to download source code:
```
git clone https://github.com/ataraxialinux/ataraxia
```
If you want to switch to specific version:
```
git checkout [Ataraxia Linux version]
```

## Index of source packages
We have separated packages into groups to make the build system cleaner. We have following repositories for packages:
```
 * community    - Packages maintained by Ataraxia Linux community. Not supported by core team
 * experimental - Unstable packages mostly for testing new features and adding new packages
 * packages     - Main packages collection for Linux distribution
 * toolchain    - Packages to build cross-toolchain [mostly required to build basic system]
```

See [bootstrapping.](bootstrapping.md)
