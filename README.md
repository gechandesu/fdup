# fdup

The dumb tool for finding duplicate files by their hash sums.

Compile it with `-prod` for better performance:

```console
$ v -prod .
```

Look at releases page for prebuilt executables.

# Synonsis

```
Usage: fdup [flags] [commands] [DIR...]

File duplicates finder

Flags:
  -hash               Hashing algorythm: blake3, crc32, fnv1a, sha1, sha256, md5 [default: fnv1a]
  -threads            Number of threads used for calculating hash sums [default: number of CPU cores]
  -brief              Brief output, print plain easy to parse hashes and filenames only.
  -json               Print output in JSON format.
  -exclude            Glob pattern to exclude files and directories [can be passed multiple times]
  -skip-empty         Skip empty files.
  -max-size           Maximum file size in bytes. Files larger than this will be skipped.
  -remove             Remove duplicates.
  -prompt             Prompt before every removal.
  -help               Prints help information.
  -version            Prints version information.

Commands:
  help                Prints help information.
  version             Prints version information.
```
