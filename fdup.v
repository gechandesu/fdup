// fdup - file duplicates finder
// Copyright (C) 2025 Ge <ge@phreepunk.network>
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

module main

import os
import cli
import arrays
import maps
import hash.crc32
import hash.fnv1a
import crypto.blake3
import crypto.sha1
import crypto.sha256
import crypto.md5
import runtime
import term
import time
import x.json2 as json

fn main() {
	mut app := cli.Command{
		name:        'fdup'
		description: 'File duplicates finder'
		version:     '0.2.0'
		usage:       '[DIR...]'
		execute:     find
		defaults:    struct {
			man: false
		}
		flags:       [
			cli.Flag{
				flag:          .string
				name:          'hash'
				description:   'Hashing algorythm: blake3, crc32, fnv1a, sha1, sha256, md5 [default: fnv1a]'
				default_value: ['fnv1a']
			},
			cli.Flag{
				flag:          .int
				name:          'threads'
				description:   'Number of threads used for calculating hash sums [default: number of CPU cores]'
				default_value: [runtime.nr_cpus().str()]
			},
			cli.Flag{
				flag:        .bool
				name:        'brief'
				description: 'Brief output, print plain easy to parse hashes and filenames only.'
			},
			cli.Flag{
				flag:        .bool
				name:        'json'
				description: 'Print output in JSON format.'
			},
			cli.Flag{
				flag:        .string_array
				name:        'exclude'
				description: 'Glob pattern to exclude files and directories [can be passed multiple times]'
			},
			cli.Flag{
				flag:        .bool
				name:        'skip-empty'
				description: 'Skip empty files.'
			},
			cli.Flag{
				flag:        .string
				name:        'max-size'
				description: 'Maximum file size in bytes. Files larger than this will be skipped.'
			},
			cli.Flag{
				flag:        .bool
				name:        'remove'
				description: 'Remove duplicates.'
			},
			cli.Flag{
				flag:        .bool
				name:        'prompt'
				description: 'Prompt before every removal.'
			},
		]
	}
	app.setup()
	app.parse(os.args)
}

fn find(cmd cli.Command) ! {
	hash_fn := HashFn.from_string(cmd.flags.get_string('hash')!) or { HashFn.fnv1a }
	nr_threads := cmd.flags.get_int('threads')!
	brief_output := cmd.flags.get_bool('brief')!
	json_output := cmd.flags.get_bool('json')!
	exclude_globs := cmd.flags.get_strings('exclude')!
	skip_empty := cmd.flags.get_bool('skip-empty')!
	max_size := cmd.flags.get_string('max-size')!.u64()
	remove := cmd.flags.get_bool('remove')!
	prompt := cmd.flags.get_bool('prompt')!
	if nr_threads <= 0 {
		eprintln('threads number cannot be zero or negative')
		exit(1)
	}
	mut search_paths := ['.']
	if cmd.args.len > 0 {
		search_paths = cmd.args.clone()
	}
	// collect full list of files absolute paths
	mut file_paths := &[]string{}
	outer: for search_path in search_paths {
		if search_path != '.' {
			for glob in exclude_globs {
				if search_path.match_glob(glob) {
					continue outer
				}
			}
		}
		if !os.is_dir(search_path) {
			eprintln('${search_path} is not a directory, skip')
			continue
		}
		norm_path := os.norm_path(os.abs_path(os.expand_tilde_to_home(search_path)))
		os.walk(norm_path, fn [mut file_paths, exclude_globs, skip_empty, max_size] (file string) {
			for glob in exclude_globs {
				if file.match_glob(glob) || os.file_name(file).match_glob(glob) {
					return
				}
			}
			mut file_size := u64(0)
			if skip_empty || max_size > 0 {
				file_size = os.file_size(file)
			}
			if skip_empty && file_size == 0 {
				return
			}
			if max_size > 0 && file_size > max_size {
				return
			}
			file_paths << file
		})
	}
	if file_paths.len == 0 {
		eprintln('nothing to do, exiting')
		exit(1)
	}
	eprintln('found ${file_paths.len} files, processing...')
	// split the files list into approximately equal parts by the number of threads
	mut parts := [][]string{}
	if nr_threads == 1 {
		parts = [*file_paths]
	} else if nr_threads >= file_paths.len {
		for path in file_paths {
			parts << [path]
		}
	} else {
		parts = arrays.chunk(*file_paths, file_paths.len / nr_threads)
		mut idx := 0
		for parts.len != nr_threads {
			parts[idx] = arrays.append(parts[0], parts.last())
			parts.delete_last()
			idx++
			if idx >= parts.len {
				idx = 0
			}
		}
	}
	// calculate hashsums in parallel
	mut threads := []thread map[string]string{}
	for i := 0; i < parts.len; i++ {
		threads << spawn calculate_hashsums(i, parts[i], hash_fn)
	}
	calculated := threads.wait()
	mut sums := map[string]string{}
	for s in calculated {
		maps.merge_in_place(mut sums, s)
	}
	// find and pretty-print duplicates
	dups := find_duplicates(sums)
	if dups.len == 0 {
		eprintln(term.bold('no duplicates found'))
		exit(0)
	}
	if brief_output {
		for hash, files in dups {
			for file in files {
				println(hash + ':' + file)
			}
		}
	} else if json_output {
		mut output := OutputSchema{
			hash_fn: hash_fn.str()
		}
		for hash, files in dups {
			mut entries := []FileEntry{}
			for file in files {
				stat := os.stat(file)!
				entries << FileEntry{
					path:  file
					size:  stat.size
					mtime: time.unix(stat.mtime)
				}
			}
			output.data << Duplicate{
				hash:  hash
				total: entries.len
				files: entries
			}
		}
		println(json.encode[OutputSchema](output))
	} else {
		for hash, files in dups {
			println(term.bold(hash))
			for file in files {
				stat := os.stat(file)!
				println('\t${time.unix(stat.mtime)} ${stat.size:-10} ${file}')
			}
		}
	}
	if remove {
		for _, files in dups {
			for file in files[1..] {
				if prompt {
					answer := os.input("delete file '${file}'? (y/n): ")
					if answer != 'y' {
						eprintln('skipped ${file}')
						continue
					}
				}
				os.rm(file)!
			}
		}
	}
}

struct OutputSchema {
	hash_fn string
mut:
	data []Duplicate
}

struct Duplicate {
	hash  string
	total int
	files []FileEntry
}

struct FileEntry {
	path  string
	size  u64
	mtime time.Time
}

fn find_duplicates(files map[string]string) map[string][]string {
	mut dups := map[string][]string{}
	for _, hash in files {
		if hash !in dups {
			for f, h in files {
				if h == hash {
					dups[hash] << f
				}
			}
		}
	}
	for h, f in dups {
		if f.len == 1 {
			dups.delete(h)
		}
	}
	return dups
}

enum HashFn {
	blake3
	crc32
	fnv1a
	sha1
	sha256
	md5
}

fn hashsum(file string, hash_fn HashFn) !string {
	file_bytes := os.read_bytes(file)!
	defer {
		unsafe { file_bytes.free() }
	}
	match hash_fn {
		.blake3 {
			return blake3.sum256(file_bytes).hex()
		}
		.crc32 {
			return crc32.sum(file_bytes).hex()
		}
		.fnv1a {
			return fnv1a.sum64(file_bytes).hex()
		}
		.sha1 {
			return sha1.sum(file_bytes).hex()
		}
		.sha256 {
			return sha256.sum(file_bytes).hex()
		}
		.md5 {
			return md5.sum(file_bytes).hex()
		}
	}
}

fn calculate_hashsums(tid int, files []string, hash_fn HashFn) map[string]string {
	eprintln('thread ${tid} started with queue of ${files.len} files')
	mut sums := map[string]string{}
	for file in files {
		sums[file] = hashsum(file, hash_fn) or {
			eprintln('File ${file} is skipped due read error: ${err}')
			continue
		}
	}
	return sums
}
