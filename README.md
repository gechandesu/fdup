# fdup

The dumb tool to find duplicate files by it's hash sums.

Compile it with `-prod` for better performance:

```console
$ v -prod .
```

Look at releases page for prebuilt executables.

# Synonsis

```
Usage: fdup [flags] [commands] [path...]

File duplicates finder

Flags:
  -hash               Set hashing algorythm: blake3, sha1, sha256, md5 [default: md5]
  -threads            Number of threads used for calculating hash sums [default: number of CPU cores]
  -brief              Brief output, print plain easy to parse hashes and filenames only
  -help               Prints help information.
  -version            Prints version information.

Commands:
  help                Prints help information.
  version             Prints version information.
```
