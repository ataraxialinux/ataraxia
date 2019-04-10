 
### Building
We have seperated the build process into seperate "stages":
```
 * 0          - This stage intended to compile cross-toolchain
 * 1          - This stage intended to compile basic target system with cross-compiler (You don't need to compile stage 0)
 * 1a         - Resume stage 1, if you encounter a failure 
 * 1-embedded - This stage intended to compile small embedded system with cross-compiler (You don't need to compile stage 0)
 * 2          - This stage is intended to generate .iso, hard disk and stage images
 * 2-embedded - This stage is intended to generate hard disk and stage images for embedded devices
 * all        - Performs stages 0, 1 and 2 automatically

```
To begin the build process, **as root**:
```
BARCH=[supported architecture] ./build stage [stage number]
```
See [supported platforms and architecures.](plaftorms.md)
And magic happens!
