# Submiting new packages

In order to submit new package you **MUST** follow the code style. 

## Number sign fields
Let's look at "number sign info". Here's the correct example of it:
```
# Description: The GNU Compiler Collection
# URL:         http://gcc.gnu.org
# Maintainer:  protonesso, nagakamira at gmail dot com
# Depends on:  mpc binutils zstd
# Section:     devel
```

The field `Description` should have short description of package. It's required field.

The field `URL` should have package homepage. It's required field.

The field `Maintainer` should have package maintainer nickname and email address. It's required field.

**NOTE**: Don't forget email address, don't put email address like this: `nagakamira@gmail.com`, `nagakamira at gmail dot com` only. Don't put your name and last name, don't put stuff like 'aka', don't use any kind of brackets.

The field `Depends on` should have package dependencies. It's optional field.

**NOTE**: Put build depends in the front. Put build systems in the front, then compilers, interpreters and other build dependencies. Don't add dependencies like: `gcc binutils pkgconf musl make` unless they required at runtime (except for musl and make). If your package depends on libtool's libltdl then add package called `libltdl`.

The field "Dep [architecture]" should have platform specific dependencies. It's optional field.

The field `Conflicts with` should have package conflicts. It's optional field.

The field `Obsoletes` should have package obsoletes. It's optional field.

## Port information variables
In order to succesfully build a package you must have following variables:
```
name
version
release
```

**NOTE**: `release=` should not be equal zero (0). `version=` should not have dash sign (`-`), replace it with `+`.

Also you can specify: `source, options, backup and noextract`.

Here's the correct example of them:
```
backup=('etc/xml/catalog')
options=('~strip')
source=("http://distfiles.gentoo.org/distfiles/docbook-xml-4.5.zip"
	"http://www.docbook.org/xml/4.4/docbook-xml-4.4.zip"
	"http://www.docbook.org/xml/4.3/docbook-xml-4.3.zip"
	"http://www.docbook.org/xml/4.2/docbook-xml-4.2.zip"
	"http://www.docbook.org/xml/4.1.2/docbkx412.zip")
noextract=("docbook-xml-4.5.zip"
	"docbook-xml-4.4.zip"
	"docbook-xml-4.3.zip"
	"docbook-xml-4.2.zip"
	"docbkx412.zip")
```

Also you should use this order: `backup, options, sources and then noextract`

## Build function:
You must have build function to compile the package. Use following examples if you're targeting specific build system:
```
m4 - autotools (eg. ./configure make make install)
cmake - snappy
meson - gnome-weather
```

**NOTE**: Always use samurai if using cmake.

Applying patches should look like this:
```
  cd "$SRC"/$name-$version
  patch -Np1 -i "$STUFF"/[package name, don't use variables]/file.patch
  <- leave the space
  [do autoreconf if required]
  build commands...
```
  
Specifying PKG and SRC variables should look like this:
```
"$SRC"/file
"$PKG"/usr/bin/file
```

and not like this:
```
"$SRC/file"
"$PKG/usr/bin/file"
$SRC/file
$PKG/usr/bin/file
```

After performing installation steps **LEAVE THE SPACE** and add needed files and configuration files:
```
  make DESTDIR="$PKG" install
  <- leave the space
  install -Dm644 "$STUFF"/[package name, don't use variables]/file "$PKG"/usr/bin/file
```

If you wish to modify file after configuration but before build leave the space and modify file:
```
  ./configure $BUILDFLAGS \
      --prefix=/usr
  <- leave the space
  sed -i 's/foo/bar/g' Makefile
  make
  make DESTDIR="$PKG" install
```

## General code style advices
**NEVER USE SPACES, ALWAYS USE TABS**. If you're trying to add C or C++ code use Google's C++ style.

If the requirements are not met, then the pull request will be closed without explanation.

Ataraxia Linux development team
