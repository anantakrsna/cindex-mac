#!/bin/bash
#
# build-universal-libs.sh
#
# Rebuilds the static libraries bundled in macports/ as universal binaries
# (Apple silicon arm64 + Intel x86_64), so Cindex can be built to run natively
# on both kinds of Mac.
#
# The versions match the headers already in macports/ (checked file by file):
#   ICU 58.2, hunspell 1.6.2 (headers identical to 1.6.1), expat 2.1.0, libiconv 1.15
# The headers in macports/ are left untouched; only the .a files are replaced.
#
# Usage (from Terminal, in the project folder):
#   ./macports/build-universal-libs.sh
#
# Needs: Xcode (or the Command Line Tools) and an internet connection.
# On an Apple silicon Mac it also needs Rosetta, to run the Intel half of the
# ICU build:  softwareupdate --install-rosetta --agree-to-license
#
# The original Intel-only libraries are copied to the work folder first, and are
# also in git, so `git checkout -- macports` puts them back.

set -euo pipefail

MACPORTS="$(cd "$(dirname "$0")" && pwd)"
WORK="${CINDEX_LIBS_WORK:-$HOME/Library/Caches/cindex-universal-libs}"
JOBS="$(sysctl -n hw.ncpu)"
ARCHS=(arm64 x86_64)
HOST_ARCH="$(uname -m)"          # arm64 on Apple silicon, x86_64 on Intel
export MACOSX_DEPLOYMENT_TARGET=12.0    # same as the Xcode project (Xcode 27 supports 12.0 and later)

# Newer Xcode compilers turn some old-C warnings into errors; these old
# configure scripts and sources need them to stay warnings.
CWARN="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"

ICU_URL="https://github.com/unicode-org/icu/releases/download/release-58-2/icu4c-58_2-src.tgz"
ICU_SHA="2b0a4410153a9b20de0e20c7d8b66049a72aef244b53683d0d7521371683da0c"
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_2_1_0/expat-2.1.0.tar.gz"
EXPAT_SHA="823705472f816df21c8f6aa026dd162b280806838bb55b3432b0fb1fcca7eb86"
HUNSPELL_URL="https://github.com/hunspell/hunspell/archive/refs/tags/v1.6.2.tar.gz"
ICONV_URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

triple() {
	case "$1" in
		arm64)  echo aarch64-apple-darwin ;;
		x86_64) echo x86_64-apple-darwin ;;
	esac
}

# Can this Mac run programs built for $1? (needed by configure checks and ICU's data tools)
can_run() {
	[ "$1" = "$HOST_ARCH" ] && return 0
	[ "$1" = "x86_64" ] && [ "$HOST_ARCH" = "arm64" ] && arch -x86_64 /usr/bin/true 2>/dev/null
}

fetch() {	# fetch URL FILE [SHA256]
	local url="$1" file="$WORK/dl/$2" sha="${3:-}"
	if [ ! -s "$file" ]; then
		echo "Downloading $url"
		curl -fL --retry 3 -o "$file.part" "$url" && mv "$file.part" "$file"
	fi
	if [ -n "$sha" ]; then
		echo "$sha  $file" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $file (delete it and run again)"
	else
		echo "  sha256: $(shasum -a 256 "$file" | cut -d' ' -f1)"
	fi
}

fresh_src() {	# fresh_src ARCHIVE DIR  -> unpacks ARCHIVE into an empty DIR
	rm -rf "$2"; mkdir -p "$2"
	tar xzf "$WORK/dl/$1" -C "$2" --strip-components=1
}

# ---------------------------------------------------------------------------
command -v clang >/dev/null || die "clang not found. Install Xcode or run: xcode-select --install"
if [ "$HOST_ARCH" = arm64 ] && ! can_run x86_64; then
	die "Rosetta is needed for the Intel half of the build. Run: softwareupdate --install-rosetta --agree-to-license"
fi

mkdir -p "$WORK/dl" "$WORK/out"
say "Work folder: $WORK"

fetch "$ICU_URL"      icu4c-58_2-src.tgz "$ICU_SHA"
fetch "$EXPAT_URL"    expat-2.1.0.tar.gz "$EXPAT_SHA"
fetch "$HUNSPELL_URL" hunspell-1.6.2.tar.gz 3cd9ceb062fe5814f668e4f22b2fa6e3ba0b339b921739541ce180cac4d6f4c4
fetch "$ICONV_URL"    libiconv-1.15.tar.gz ccf536620a45458d26ba83887a983b96827001e92a13847b45e4925cc8913178

# ---------------------------------------------------------------------------
# ICU 58.2 (libicuuc, libicui18n, libicuio, libicudata)
# The arch this Mac runs natively is built first, because a cross build (arm64
# on an Intel Mac) needs that build's tools to package the ICU data.
build_icu() {
	local a="$1" src="$WORK/icu-$1" extra=()
	say "ICU 58.2 for $a"
	fresh_src icu4c-58_2-src.tgz "$src"
	local build_arch="$a"
	if ! can_run "$a"; then
		build_arch="$HOST_ARCH"
		extra=(--with-cross-build="$WORK/icu-$HOST_ARCH/source")
	fi
	( cd "$src/source"
	  CC="clang -arch $a" CXX="clang++ -arch $a" \
	  CFLAGS="-O2 $CWARN" CXXFLAGS="-O2 -std=c++11" \
	  ./configure --build="$(triple "$build_arch")" --host="$(triple "$a")" \
		--enable-static --disable-shared --with-data-packaging=static \
		--disable-tests --disable-samples --disable-extras \
		${extra[@]+"${extra[@]}"} > "$WORK/icu-$a-configure.log" 2>&1 \
		|| die "ICU configure failed for $a; see $WORK/icu-$a-configure.log"
	  make -j"$JOBS" > "$WORK/icu-$a-make.log" 2>&1 \
		|| die "ICU build failed for $a; see the end of $WORK/icu-$a-make.log"
	)
	mkdir -p "$WORK/out/$a"
	for l in icuuc icui18n icuio icudata; do
		cp "$src/source/lib/lib$l.a" "$WORK/out/$a/lib$l.a"
	done
}

ICU_ORDER=("$HOST_ARCH")
for a in "${ARCHS[@]}"; do
	if [ "$a" != "$HOST_ARCH" ]; then ICU_ORDER+=("$a"); fi
done
for a in "${ICU_ORDER[@]}"; do build_icu "$a"; done

# ---------------------------------------------------------------------------
# libiconv 1.15 (libiconv, libcharset)
for a in "${ARCHS[@]}"; do
	say "libiconv 1.15 for $a"
	src="$WORK/iconv-$a"
	fresh_src libiconv-1.15.tar.gz "$src"
	build_arch="$a"; can_run "$a" || build_arch="$HOST_ARCH"
	( cd "$src"
	  CC="clang -arch $a" CFLAGS="-O2 $CWARN" \
	  ./configure --build="$(triple "$build_arch")" --host="$(triple "$a")" \
		--enable-static --disable-shared --disable-nls \
		> "$WORK/iconv-$a-configure.log" 2>&1 \
		|| die "libiconv configure failed for $a; see $WORK/iconv-$a-configure.log"
	  # only the two libraries are needed, not the iconv command-line program
	  { make -C libcharset -j"$JOBS" && make -C lib -j"$JOBS"; } > "$WORK/iconv-$a-make.log" 2>&1 \
		|| die "libiconv build failed for $a; see the end of $WORK/iconv-$a-make.log"
	)
	cp "$src/lib/.libs/libiconv.a"            "$WORK/out/$a/libiconv.a"
	cp "$src/libcharset/lib/.libs/libcharset.a" "$WORK/out/$a/libcharset.a"
done

# ---------------------------------------------------------------------------
# expat 2.1.0 and hunspell 1.6.2: small, so compiled directly for both archs at once
ARCHFLAGS="-arch arm64 -arch x86_64"

say "expat 2.1.0 (universal)"
src="$WORK/expat"; fresh_src expat-2.1.0.tar.gz "$src"
( cd "$src/lib"
  clang $ARCHFLAGS -O2 $CWARN -DHAVE_MEMMOVE -DXML_NS -DXML_DTD -DXML_CONTEXT_BYTES=1024 -DBYTEORDER=1234 \
	-c xmlparse.c xmlrole.c xmltok.c
  rm -f libexpat.a; ar rcs libexpat.a xmlparse.o xmlrole.o xmltok.o
) || die "expat build failed"
cp "$src/lib/libexpat.a" "$WORK/out/libexpat.a"

say "hunspell 1.6.2 (universal)"
src="$WORK/hunspell"; fresh_src hunspell-1.6.2.tar.gz "$src"
( cd "$src/src/hunspell"
  # utf_info.cxx is #included by csutil.cxx, so it is not compiled on its own
  clang++ $ARCHFLAGS -O2 -DBUILDING_LIBHUNSPELL \
	-c affentry.cxx affixmgr.cxx csutil.cxx hashmgr.cxx hunspell.cxx \
	   suggestmgr.cxx phonet.cxx filemgr.cxx hunzip.cxx replist.cxx
  rm -f libhunspell-1.6.a; ar rcs libhunspell-1.6.a ./*.o
) || die "hunspell build failed"
cp "$src/src/hunspell/libhunspell-1.6.a" "$WORK/out/libhunspell-1.6.a"

# ---------------------------------------------------------------------------
say "Combining into universal libraries"
for l in icuuc icui18n icuio icudata iconv charset; do
	lipo -create "$WORK/out/arm64/lib$l.a" "$WORK/out/x86_64/lib$l.a" -output "$WORK/out/lib$l.a"
done

say "Installing into $MACPORTS (originals saved in $WORK/originals)"
install_lib() {	# install_lib NAME DEST_SUBDIR
	mkdir -p "$WORK/originals/$2"
	if [ -f "$MACPORTS/$2/$1" ] && [ ! -f "$WORK/originals/$2/$1" ]; then
		cp "$MACPORTS/$2/$1" "$WORK/originals/$2/$1"
	fi
	cp "$WORK/out/$1" "$MACPORTS/$2/$1"
	printf '  %-22s %s\n' "$1" "$(lipo -archs "$MACPORTS/$2/$1")"
}
install_lib libicuuc.a          ICU/lib
install_lib libicui18n.a        ICU/lib
install_lib libicuio.a          ICU/lib
install_lib libicudata.a        ICU/lib
install_lib libiconv.a          libiconv/lib
install_lib libcharset.a        libiconv/lib
install_lib libexpat.a          expat/lib
install_lib libhunspell-1.6.a   hunspell/lib

say "Done. Every library above should list: x86_64 arm64"
echo "Next: open Cindex.xcodeproj, choose the destination 'My Mac', and build (Cmd-B)."
