#!/usr/bin/env bats

@test "transient-folder-snapshot --help" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot --help

	[[ "$output" =~ Usage:\ transient-folder-snapshot ]]
	[ "$status" -eq 0 ]
}
@test "transient-folder-snapshot: To few parameters" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot . --

	[[ "$output" =~ Error:\ Expected\ at\ least ]]
	[[ "$output" =~ Usage:\ transient-folder-snapshot ]]
	[ "$status" -eq 1 ]
}
@test "transient-folder-snapshot" {
	tmpdir="$(mktemp -d)"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]

	rm -rf "$tmpdir"
}
@test "transient-folder-snapshot: Empty exclude" {
	tmpdir="$(mktemp -d)"
	echo 4 > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,exclude=,exclude=,nopreservegroup" -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "4" ]

	rm -rf "$tmpdir"
}
@test "transient-folder-snapshot: Non-existent folder" {
	tmpdir="$(mktemp -d)"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" /does-not-exist -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Could not find folder /does-not-exist for snapshotting." ]

	rm -rf "$tmpdir"
}
@test "transient-folder-snapshot: Exit code" {
	tmpdir="$(mktemp -d)"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]

	rmdir "$tmpdir"
}
@test "transient-folder-snapshot: Trailing slash" {
	tmpdir="$(mktemp -d)"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir/" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]

	rm -rf "$tmpdir"
}
@test "transient-folder-snapshot: Folder with spaces" {
	mkdir -p /tmp/"transient folder snapshot test"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot /tmp/"transient folder snapshot test" -- \
		sh -c 'cd /tmp/"transient folder snapshot test"; echo CONTENT > a; cat a'
	[ "$status" -eq 0 ]
	[ "$output" == "CONTENT" ]
	[ ! -f /tmp/"transient folder snapshot test"/a ]

	rm -rf /tmp/"transient folder snapshot test"
}
@test "transient-folder-snapshot: Folder with new lines" {
	DIRNAME="$(echo -e "/tmp/transient folder snapshot\ntest/")"
	mkdir -p "$DIRNAME"
	echo EXCLUDED > "$DIRNAME/stuff"
	echo -n a > "$DIRNAME/CONTENT"

	# shellcheck disable=SC2016
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$DIRNAME,exclude=stuff" -- \
		sh -c 'cd "$1"; echo -n b >> CONTENT; cat *' -- "$DIRNAME"
	[ "$status" -eq 0 ]
	[ "$output" == "ab" ]
	[ "$(cat "$DIRNAME/CONTENT")" == "a" ]

	rm -rf "$DIRNAME"
}
@test "transient-folder-snapshot: Multiple folders" {
	mkdir -p /tmp/transient-folder-snapshot-test/data /tmp/transient-folder-snapshot-test/blah /tmp/transient-folder-snapshot-test_1

	echo 1 > /tmp/transient-folder-snapshot-test/file.small
	echo 2 > /tmp/transient-folder-snapshot-test/file.large
	echo BLAH > /tmp/transient-folder-snapshot-test/data/stuff
	echo HELLO > /tmp/transient-folder-snapshot-test/blah/foo.bar
	echo SHOULD_NOT_GET_EXCLUDED > /tmp/transient-folder-snapshot-test_1/file.large

	# This should not affect the real copy of these files
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot /tmp/transient-folder-snapshot-test_1 /tmp/transient-folder-snapshot-test,exclude=blah,exclude=*.large --\
		find /tmp/transient-folder-snapshot-test* -type f -delete
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot /tmp/transient-folder-snapshot-test_1 /tmp/transient-folder-snapshot-test,exclude=blah,exclude=*.large --\
		find /tmp/transient-folder-snapshot-test*
	[ "$status" -eq 0 ]

	[[ "$output" =~ /tmp/transient-folder-snapshot-test/file.small ]]
	[[ "$output" =~ /tmp/transient-folder-snapshot-test/data/stuff ]]
	[[ "$output" =~ /tmp/transient-folder-snapshot-test_1/file.large ]]
	# Excluded files
	[[ ! "$output" =~ /tmp/transient-folder-snapshot-test/file.large ]]
	[[ ! "$output" =~ /tmp/transient-folder-snapshot-test/blah/foo.bar ]]

	rm -rf /tmp/transient-folder-snapshot-test*
}
@test "transient-folder-snapshot: Fails nicely if wrapping fails" {
	run sh -c 'cat '"$BATS_TEST_DIRNAME"'/transient-folder-snapshot | bash /dev/stdin -- . -- true'
	[ "$output" == "Error: Could not locate own location (needed for wrapped execution)." ]
	[ "$status" -eq 255 ]
}
@test "transient-folder-snapshot: Map user/gid" {
	tmpdir="$(mktemp -d)"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- id -u
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -u)" ]
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- id -g
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -g)" ]

	rm -rf "$tmpdir"
}
@test "transient-folder-snapshot: Argument parsing (exclude, nopreservegroup and nopreserveowner)" {
	rm -f /tmp/transient-folder-snapshot.log
	tmpdir="$(mktemp -d)"
	tmpbindir="$(mktemp -d)"

	echo '#!/bin/bash' > "$tmpbindir"/rsync
	echo 'echo "rsync $@" >> /tmp/transient-folder-snapshot.log' >> "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot \
		"$tmpdir,nopreservegroup,nopreserveowner" \
		"$tmpdir,nopreservegroup" \
		"$tmpdir,nopreserveowner" \
		"$tmpdir" \
		"$tmpdir,exclude=Blah blub" \
		"$tmpdir,exclude=a*,nopreserveowner,exclude=blah" \
		-- true

	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	run cat /tmp/transient-folder-snapshot.log
	rm -f /tmp/transient-folder-snapshot.log
	
	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ -g\ / ]]
	[[ "${lines[3]}" =~ ^rsync\ -rlptD\ -g\ -o\ / ]]
	[[ "${lines[4]}" =~ ^rsync\ -rlptD\ -g\ -o\ --exclude\ Blah\ blub\ / ]]
	[[ "${lines[5]}" =~ ^rsync\ -rlptD\ -g\ --exclude\ a\*\ --exclude\ blah\ / ]]

	rm -rf "$tmpdir" "$tmpbindir"
}
@test "transient-folder-snapshot: rsync error handling" {
	rm -f /tmp/transient-folder-snapshot.log
	tmpdir="$(mktemp -d)"

	tmpbindir="$(mktemp -d)"
	{
		echo '#!/bin/bash'
		echo 'echo "rsync $@" >> /tmp/transient-folder-snapshot.log'
		echo 'echo "rsync error" >&2'
		echo 'exit 42'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot --verbose "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot --debug "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run cat /tmp/transient-folder-snapshot.log
	rm -f /tmp/transient-folder-snapshot.log
	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ -g\ -o\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ -g\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ -g\ -o\ /.*\ /.*\ --progress ]]

	rm -rf "$tmpdir" "$tmpbindir"
}
@test "transient-folder-snapshot: mount error handling" {
	tmpdir="$(mktemp -d)"
	tmpbindir="$(mktemp -d)"

	function MOCK_MOUNT {
		echo '#!/bin/bash' > "$tmpbindir"/mount
		if [ "$1" == "bind" ]; then
			echo 'if [[ "$@" =~ --bind ]]; then echo "Bind mount fail"; exit 1; fi' >> "$tmpbindir"/mount
		elif [ "$1" == "tmpfs" ]; then
			echo 'if [[ "$@" =~ tmpfs ]]; then echo "tmpfs mount fail"; exit 1; fi' >> "$tmpbindir"/mount
		fi
		echo 'exec /usr/bin/mount "$@"' >> "$tmpbindir"/mount
		chmod +x "$tmpbindir"/mount
	}

	MOCK_MOUNT bind
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[ "$output" == "Error: mount --bind failed: Bind mount fail" ]

	MOCK_MOUNT tmpfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[[ "$output" =~ ^Error:\ Mounting\ tmpfs\ to\ \"/.*\":\ tmpfs\ mount\ fail$ ]]

	rm -rf "$tmpdir" "$tmpbindir"
}
@test "transient-folder-snapshot --debug" {
	tmpdir="$(mktemp -d)"
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ rsync\ -.*\ --progress ]]
	# to-chk is included in rsync --progress, thus check for that
	[[ "$output" =~ to-chk ]]

	rm -rf "$tmpdir"
}
