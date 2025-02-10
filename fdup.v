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
import crypto.blake3
import crypto.sha1
import crypto.sha256
import crypto.md5
import runtime
import term
import time

fn main() {
	mut app := cli.Command{
		name:        'fdup'
		description: 'File duplicates finder'
		version:     '0.1.0'
		usage:       '[path...]'
		execute:     find
		defaults:    struct {
			man: false
		}
		flags:       [
			cli.Flag{
				flag:          .string
				name:          'hash'
				description:   'Set hashing algorythm: blake3, sha1, sha256, md5 [default: md5]'
				default_value: ['md5']
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
				description: 'Brief output, print plain easy to parse hashes and filenames only'
			},
		]
	}
	app.setup()
	app.parse(os.args)
}

fn find(cmd cli.Command) ! {
	hash_algo := HashAlgo.from_string(cmd.flags.get_string('hash')!) or { HashAlgo.md5 }
	nr_threads := cmd.flags.get_int('threads')!
	brief := cmd.flags.get_bool('brief')!
	mut search_paths := ['.']
	if cmd.args.len > 0 {
		search_paths = cmd.args.clone()
	}
	// collect full list of files absolute paths
	mut file_paths := &[]string{}
	for search_path in search_paths {
		norm_path := os.norm_path(os.abs_path(os.expand_tilde_to_home(search_path)))
		os.walk(norm_path, fn [mut file_paths] (file string) {
			file_paths << file
		})
	}
	eprintln('found ${file_paths.len} files, processing...')
	// split the files list into approximately equal parts by the number of threads
	mut parts := [][]string{}
	if nr_threads == 1 {
		parts = [*file_paths]
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
	for i := 0; i < nr_threads; i++ {
		threads << spawn calculate_hashsums(parts[i], hash_algo)
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
	for hash, files in dups {
		if brief {
			for file in files {
				println(hash + ':' + file)
			}
		} else {
			println(term.bold(hash))
			for file in files {
				stat := os.stat(file)!
				println('\t${time.unix(stat.mtime)}\t${file}')
			}
		}
	}
	exit(2)
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

enum HashAlgo {
	blake3
	sha1
	sha256
	md5
}

fn hashsum(file string, algo HashAlgo) string {
	file_bytes := os.read_bytes(file) or { []u8{len: 1} }
	defer {
		unsafe { file_bytes.free() }
	}
	match algo {
		.blake3 {
			return blake3.sum256(file_bytes).hex()
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

fn calculate_hashsums(files []string, hash HashAlgo) map[string]string {
	mut sums := map[string]string{}
	for file in files {
		sums[file] = hashsum(file, hash)
	}
	return sums
}
