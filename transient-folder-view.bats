#!/usr/bin/env bats

can_use_fuse_overlayfs=""
if command -v fuse-overlayfs >/dev/null && [[ "$(lsmod)" =~ fuse\  ]]; then
	can_use_fuse_overlayfs=1
fi

setup() {
	tmpdir="$(mktemp --tmpdir -d transient-folder-view-bats.tmpdir.XXXXXXXXXX)"
	tmpbindir="$(mktemp --tmpdir -d transient-folder-view-bats.tmpbindir.XXXXXXXXXX)"
}
teardown() {
	rm -rf "$tmpdir" "$tmpbindir"
}

@test "transient-folder-view --help" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view --help
	[ "$status" -eq 0 ]

	[[ "$output" =~ Usage:\ transient-folder-view ]]
	[[ "$output" =~ toleratepartialtransfer ]]
	[[ "$output" =~ if\ set,\ don\'t\ fail\ on ]]
	[[ "$output" =~ only\ to\ snapshot\ mode ]]
}
@test "transient-folder-overlay --help" {
	run "$BATS_TEST_DIRNAME"/transient-folder-overlay --help
	[ "$status" -eq 0 ]

	[[ "$output" =~ Usage:\ transient-folder-overlay ]]
	[[ ! "$output" =~ toleratepartialtransfer ]]
	[[ ! "$output" =~ if\ set,\ don\'t\ fail\ on ]]
	[[ ! "$output" =~ only\ to\ snapshot\ mode ]]
}
@test "transient-folder-snapshot --help" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot --help
	[ "$status" -eq 0 ]

	[[ "$output" =~ Usage:\ transient-folder-snapshot ]]
	[[ "$output" =~ toleratepartialtransfer ]]
	[[ "$output" =~ if\ set,\ don\'t\ fail\ on ]]
	[[ ! "$output" =~ only\ to\ snapshot\ mode ]]
}
@test "transient-folder-snapshot: Too few parameters" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot

	[[ "$output" =~ Error:\ Expected\ at\ least ]]
	[[ "$output" =~ Usage:\ transient-folder-snapshot ]]
	[ "$status" -eq 1 ]
}
@test "transient-folder-snapshot" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
}
@test "transient-folder-view snapshot" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view snapshot "$tmpdir" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "tmpfs" ]
}
@test "transient-folder-view: No leftovers in /tmp" {
	tmp="$(dirname "$(mktemp -u --tmpdir -d)")"
	tmpFilesPrior="$(find "$tmp" -name '*transient-folder-view*' 2>/dev/null | wc -l)"

	# snapshot success
	run "$BATS_TEST_DIRNAME"/transient-folder-view snapshot "$tmpdir" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	# snapshot mount --bind will fail here
	run "$BATS_TEST_DIRNAME"/transient-folder-view snapshot /dev -- true
	[ "$status" -gt 0 ]

	# snapshot doesn't allow working on /tmp
	run "$BATS_TEST_DIRNAME"/transient-folder-view snapshot /tmp -- true
	[ "$status" -gt 0 ]

	# Make rsync fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view snapshot --debug "$tmpdir" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/rsync

	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030
	if [ -n "$can_use_fuse_overlayfs" ]; then
		# overlay success
		run "$BATS_TEST_DIRNAME"/transient-folder-view overlay "$tmpdir" -- true
		[ "$status" -eq 0 ]
		[ "$output" == "" ]

		# overlay mount --bind will fail here	
		run "$BATS_TEST_DIRNAME"/transient-folder-view overlay /dev -- true
		[ "$status" -gt 0 ]

		# overlay doesn't allow working on /tmp
		run "$BATS_TEST_DIRNAME"/transient-folder-view overlay /tmp -- true
		[ "$status" -gt 0 ]
	fi

	# Make fuse-overlayfs fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view overlay --debug "$tmpdir" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/fuse-overlayfs

	tmpFilesNow="$(find "$tmp" -name '*transient-folder-view*' 2>/dev/null | wc -l)"
	[ "$tmpFilesPrior" -eq "$tmpFilesNow" ]
}
@test "transient-folder-view overlay" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	run "$BATS_TEST_DIRNAME"/transient-folder-view overlay "$tmpdir" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "fuse.fuse-overlayfs" ]
}
@test "transient-folder-snapshot: Invalid directory options" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,nopreservegroup,banana,exclude=foo,exclude=bar," -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-snapshot --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,exclude=.git,nopreservegroup,banana,nopreserveowner" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-snapshot --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,nopreservegroup,nopreserveuser" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-snapshot --help\"." ]
}
@test "transient-folder-snapshot: Empty exclude" {
	echo 4 > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,exclude=,exclude=,nopreservegroup" -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "4" ]
}
@test "transient-folder-snapshot: Non-existent folder" {
run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" /does-not-exist -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Could not find folder \"/does-not-exist\"." ]
}
@test "transient-folder-snapshot: Exit code" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
}
@test "transient-folder-snapshot: Fails for /tmp" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot /tmp// -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
}
@test "transient-folder-snapshot: Trailing slash" {
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir/" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
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
	if [[ ! "$(unshare --help)" =~ --map-user ]]; then
		# Needs unshare with --map-user/--map-group support.
		skip
	fi

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- id -u
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -u)" ]
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- id -g
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -g)" ]
}
@test "transient-folder-snapshot: Argument parsing (exclude, nopreservegroup, nopreserveowner and toleratepartialtransfer)" {
	rm -f /tmp/transient-folder-snapshot.log

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
		"$tmpdir,exclude=meh,toleratepartialtransfer,nopreserveowner" \
		"$tmpdir,exclude=meh,nopreserveowner,toleratepartialtransfer" \
		-- true

	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	run cat /tmp/transient-folder-snapshot.log
	rm -f /tmp/transient-folder-snapshot.log

	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ / ]]
	[[ "${lines[3]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[4]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ --exclude\ Blah\ blub\ / ]]
	[[ "${lines[5]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ --exclude\ a\*\ --exclude\ blah\ / ]]
	[[ "${lines[6]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ --exclude\ meh\ / ]]
	[[ "${lines[7]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ --exclude\ meh\ / ]]
}
@test "transient-folder-snapshot: rsync error handling" {
	rm -f /tmp/transient-folder-snapshot.log

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
	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ /.*\ /.*\ --progress ]]
}
@test "transient-folder-snapshot: mount error handling" {
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
}
@test "transient-folder-snapshot --debug" {
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ rsync\ -.*\ --progress ]]
	# to-chk is included in rsync --progress, thus check for that
	[[ "$output" =~ to-chk ]]
}
@test "transient-folder-snapshot: toleratepartialtransfer" {
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-snapshot "$tmpdir,toleratepartialtransfer" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]
}
@test "transient-folder-overlay: Exit code" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	run "$BATS_TEST_DIRNAME"/transient-folder-overlay "$tmpdir" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
}
@test "transient-folder-overlay: Fails for /tmp" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	run "$BATS_TEST_DIRNAME"/transient-folder-snapshot /tmp// -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
}
@test "transient-folder-overlay --debug" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay "$tmpdir" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ fuse-overlayfs\ -o\ lowerdir=.+\ -o\ upperdir=.+\ $tmpdir ]]
}
@test "transient-folder-overlay: Multiple folders" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo -n "old" > "$tmpdir/a"
	mkdir "$tmpbindir/subfolder"
	echo "0" > "$tmpbindir/subfolder/file"

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay "$tmpdir" "$tmpbindir" -- sh -c \
		"echo -n new > $tmpdir/a; echo 1 > $tmpbindir/subfolder/file; cat $tmpdir/a $tmpbindir/subfolder/file"
	[ "$status" -eq 0 ]
	[[ "$output" == "new1" ]]
	[ "$(cat "$tmpdir"/a "$tmpbindir"/subfolder/file)" == 'old0' ]
}
@test "transient-folder-overlay: Folder with spaces" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	mkdir "$tmpdir/a folder with spaces"
	echo 0 > "$tmpdir/a folder with spaces/a file"

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay "$tmpdir/a folder with spaces" -- sh -c \
		"echo 1 > $tmpdir'/a folder with spaces/a file'; cat $tmpdir'/a folder with spaces/a file'"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	[ "$(cat "$tmpdir/a folder with spaces/a file")" == '0' ]
}
@test "transient-folder-overlay: Folder with new lines" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	local DIRNAME="$tmpdir/a folder with a "$'\n'"new line"
	mkdir "$DIRNAME"
	echo 0 > "$DIRNAME/file"

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay "$DIRNAME" -- sh -c \
		"cat \"$DIRNAME\"/file; echo 1 > \"$DIRNAME\"/file; cat \"$DIRNAME\"/file;"

	[ "$status" -eq 0 ]
	[[ "$output" == "0"$'\n'"1" ]]

	[ "$(cat "$DIRNAME/file")" == '0' ]
}
@test "transient-folder-overlay: nopreservegroup and nopreserveowner" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	if [[ ! "$(unshare --help)" =~ --map-user ]]; then
		# Needs unshare with --map-user/--map-group support.
		skip
	fi
	if [ "$(id -u)" == '0' ] || [ ! "$(stat --printf %u-%g /etc/hostname)" == "0-0" ]; then
		# This test assumes that we aren't root and that /etc/hostname has user/group root
		skip
	fi
	local NB_UID NB_GID GID
	NB_UID="$(id -u nobody)"
	NB_GID="$(id -g nobody)"
	GID="$(id -g)"
	# Yikes: The bind mount maps root:root to nobody:nobody, thus if we "preserve" the owner/group,
	# that's what we get.

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay /etc -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay /etc,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay /etc,nopreservegroup -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-overlay /etc,nopreservegroup,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$GID" ]]
}
@test "transient-folder-overlay: fuse-overlayfs error handling" {
	{
		echo '#!/bin/bash'
		echo 'exit 42'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-overlay "$tmpdir" -- true
	[[ "$output" == "Error: Mounting fuse-overlayfs failed." ]]
}
