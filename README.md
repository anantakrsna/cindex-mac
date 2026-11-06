# CINDEX for macOS
CINDEX is a software tool for professional indexers, enabling them to produce indexes in a variety of formats.

The official CINDEX 4.4 release works on any Mac computer running macOS 10.13 (High Sierra) or higher.

This fork builds CINDEX natively for both Apple silicon and Intel Macs, and requires macOS 12 (Monterey) or higher. See [Apple silicon build](#apple-silicon-build) below.

## Version 4.4 Changes
1.	Improves performance generally.
2.	Cindex provides a powerful new tool for comparing indexes. This reports differences between the indexes, and provides options to manage them.
3.	A new command enables you, in a single operation, to flip headings on multiple highlighted records in the main index view.
4.	When a record is open for editing you can invert a person's name with a simple command.

## Installers and Support

Installers and Support for Cindex 4.4 are available from [OpenCindex.com](https://www.opencindex.com/download).

## Apple silicon build

This fork of [plennie/cindex-mac](https://github.com/plennie/cindex-mac) builds CINDEX as a universal app that runs natively on Apple silicon (arm64) and on Intel (x86_64) Macs.

### What changed
- **Bundled libraries:** the static libraries in `macports/` (ICU 58.2, hunspell 1.6.2, expat 2.1.0, libiconv 1.15) were Intel-only. They have been rebuilt as universal libraries, using the same versions as before so that sorting and other behaviour do not change. The headers are unchanged.
- **`macports/build-universal-libs.sh`:** the script that rebuilds those libraries from their original sources, with the downloads checked against known checksums.
- **Xcode project:** the Intel-only architecture restriction (`VALID_ARCHS = x86_64`) has been removed. Release (Deployment) builds now include both architectures. The minimum macOS version has been raised from 10.13 to 12.0, the oldest version current Xcode can build for.

The CINDEX source code itself did not need any changes, and index files (`.ucdx`) work the same on both kinds of Mac.

### Building
1. Install Xcode from the Mac App Store.
2. Open `Cindex.xcodeproj`, choose the **Cindex 4** scheme and the **My Mac** destination, and choose Product → Run (⌘R).
3. For an app that runs on both Apple silicon and Intel Macs, choose the **Any Mac** destination, then Product → Archive.

The universal libraries are already included in the repository, so you only need to run the script below if you want to rebuild them:

```
./macports/build-universal-libs.sh
```

It needs an internet connection and, on Apple silicon, Rosetta (`softwareupdate --install-rosetta --agree-to-license`).

### Credits and licence
The original CINDEX code is by Peter Lennie / Indexing Research and is released under CC0 1.0 (see `LICENSE`). The Apple silicon changes in this fork were made with the help of Claude (Anthropic), are released under the same CC0 terms, and are free for anyone to use, including the original project. The bundled libraries keep their own licences.
