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

	# Print last output from bats' run
	# bats will not output anything, if the test succeeded.
	if [ -n "$output" ]; then
		echo "Last \$output:"
		echo "$output"
	fi
}

@test "transient-folder-view --help" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view --help
	[ "$status" -eq 0 ]

	[[ "$output" =~ Usage:\ transient-folder-view ]]
	[[ "$output" =~ toleratepartialtransfer ]]
	[[ "$output" =~ if\ set,\ don\'t\ fail\ on ]]
}
@test "transient-folder-view: Too few parameters" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view

	[[ "$output" =~ Error:\ Expected\ at\ least ]]
	[[ "$output" =~ Usage:\ transient-folder-view ]]
	[ "$status" -eq 1 ]
}
@test "transient-folder-view: Directory" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
}
@test "transient-folder-view: File" {
	# File "a" is transient, file "b" isn't.
	echo 0 > "$tmpdir"/a
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/a" -- sh -c "echo 1 > $tmpdir/a; echo 2 > $tmpdir/b; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ "$(cat "$tmpdir"/a)" == "0" ]
	[ "$(cat "$tmpdir"/b)" == "2" ]
}
@test "transient-folder-view: File debug" {
	echo 0 > "$tmpdir"/FILENAME
	run "$BATS_TEST_DIRNAME"/transient-folder-view --debug "$tmpdir/FILENAME" -- true

	[ "$status" -eq 0 ]
	[[ "$output" =~ ^Acting\ on\ file\ \".*\/FILENAME\"\.$ ]]
}
@test "transient-folder-view: File - cat failure" {
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/cat
	chmod +x "$tmpbindir"/cat
	echo 0 > "$tmpdir"/FILENAME
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/FILENAME" -- true

	[ "$status" -ne 0 ]
	[[ "$output" =~ ^Error:\ Copying\ contents\ of\ \".*\/FILENAME\"\ to\ \".*\"\.$ ]]
}
@test "transient-folder-view: File - mount failure" {
	{
		echo '#!/bin/bash'
		echo 'if [[ "$@" =~ --bind ]]; then echo "MOUNT-ERROR"; exit 1; fi'
		echo 'exec /usr/bin/mount "$@"'
	} > "$tmpbindir"/mount
	chmod +x "$tmpbindir"/mount

	echo 0 > "$tmpdir"/FILENAME
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/FILENAME" -- true

	[ "$status" -ne 0 ]
	[[ "$output" =~ ^Error:\ Mounting\ \".*\"\ to\ \".*\/FILENAME\":\ \"MOUNT-ERROR\"\.$ ]]
}
@test "transient-folder-view: snapshot" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,snapshot" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "tmpfs" ]
}
@test "transient-folder-view: No leftovers in /tmp" {
	tmp="$(dirname "$(mktemp -u --tmpdir -d)")"
	tmpFilesPrior="$(find "$tmp" -name '*transient-folder-view*' 2>/dev/null | wc -l)"

	# snapshot success
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,snapshot" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	# We don't allow working on /dev
	run "$BATS_TEST_DIRNAME"/transient-folder-view '/dev' -- true
	[ "$status" -gt 0 ]

	# We don't allow working on /tmp
	run "$BATS_TEST_DIRNAME"/transient-folder-view /tmp -- true
	[ "$status" -gt 0 ]

	# Make rsync fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view --debug "$tmpdir" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/rsync

	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030
	if [ -n "$can_use_fuse_overlayfs" ]; then
		# overlay success
		run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" -- true
		[ "$status" -eq 0 ]
		[ "$output" == "" ]
	fi

	# Make fuse-overlayfs fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view --debug "$tmpdir,overlay" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/fuse-overlayfs

	tmpFilesNow="$(find "$tmp" -name '*transient-folder-view*' 2>/dev/null | wc -l)"
	[ "$tmpFilesPrior" -eq "$tmpFilesNow" ]
}
@test "transient-folder-view: overlay" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "fuse.fuse-overlayfs" ]
}
@test "transient-folder-view: Invalid directory options" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,nopreservegroup,snapshot,banana,exclude=foo,exclude=bar," -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-view --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,exclude=.git,nopreservegroup,banana,nopreserveowner" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-view --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,snapshot,nopreservegroup,nopreserveuser" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-folder-view --help\"." ]
}
@test "transient-folder-view: Empty exclude" {
	echo 4 > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,exclude=,exclude=,nopreservegroup" -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "4" ]
}
@test "transient-folder-view: Non-existent folder" {
run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" /does-not-exist -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot act on \"/does-not-exist\": No such file or directory" ]
}
@test "transient-folder-view: Exit code" {
	maybeOverlay=",overlay"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		maybeOverlay=""
	fi

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir$maybeOverlay" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]

	mkdir "$tmpdir/a" "$tmpdir/b"
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/a$maybeOverlay" "$tmpdir/b" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
}
@test "transient-folder-view: Fails for /tmp" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view /tmp// -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
	run "$BATS_TEST_DIRNAME"/transient-folder-view /tmp//,overlay -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
}
@test "transient-folder-view: Fails for /dev" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view /dev -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /dev." ]
}
@test "transient-folder-view: Fails for /" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view /./ -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /." ]
}
@test "transient-folder-view: Trailing slash" {
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/,snapshot" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
}
@test "transient-folder-view: Folder with spaces (snapshot)" {
	mkdir -p /tmp/"transient folder snapshot test"

	run "$BATS_TEST_DIRNAME"/transient-folder-view /tmp/"transient folder snapshot test,snapshot" -- \
		sh -c 'cd /tmp/"transient folder snapshot test"; echo CONTENT > a; cat a'
	[ "$status" -eq 0 ]
	[ "$output" == "CONTENT" ]
	[ ! -f /tmp/"transient folder snapshot test"/a ]

	rm -rf /tmp/"transient folder snapshot test"
}
@test "transient-folder-view: Folder with new lines (snapshot)" {
	DIRNAME="$(echo -e "/tmp/transient folder snapshot\ntest/")"
	mkdir -p "$DIRNAME"
	echo EXCLUDED > "$DIRNAME/stuff"
	echo -n a > "$DIRNAME/CONTENT"

	# shellcheck disable=SC2016
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$DIRNAME,snapshot,exclude=stuff" -- \
		sh -c 'cd "$1"; echo -n b >> CONTENT; cat *' -- "$DIRNAME"
	[ "$status" -eq 0 ]
	[ "$output" == "ab" ]
	[ "$(cat "$DIRNAME/CONTENT")" == "a" ]

	rm -rf "$DIRNAME"
}
@test "transient-folder-view: Multiple folders" {
	mkdir -p "$tmpdir"/dirA "$tmpdir"/dirB

	echo SHOULD_NOT_GET_EXCLUDED > "$tmpdir"/dirA/file.large
	echo 1 > "$tmpdir"/dirB/file.small
	echo 2 > "$tmpdir"/dirB/file.large
	echo blah > "$tmpdir"/dirB/blah

	# This should not affect the real copy of these files
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir"/dirA "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
		find "$tmpdir"/* -type f -delete
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir"/dirA "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
		find "$tmpdir"/
	[ "$status" -eq 0 ]

	[[ "$output" =~ "$tmpdir"/dirA/file.large ]]
	# Excluded files
	[[ ! "$output" =~ "$tmpdir"/dirB/file.large ]]
	[[ ! "$output" =~ "$tmpdir"/dirB/blah ]]
}
@test "transient-folder-view: Fails nicely if wrapping fails" {
	run sh -c 'cat '"$BATS_TEST_DIRNAME"'/transient-folder-view | bash /dev/stdin -- . -- true'
	[ "$output" == "Error: Could not locate own location (needed for wrapped execution)." ]
	[ "$status" -eq 255 ]
}
@test "transient-folder-view: Map user/gid" {
	if [[ ! "$(unshare --help)" =~ --map-user ]]; then
		# Needs unshare with --map-user/--map-group support.
		skip
	fi

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- id -u
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -u)" ]
	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- id -g
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -g)" ]
}
@test "transient-folder-view: Snapshot argument parsing (exclude, nopreservegroup, nopreserveowner and toleratepartialtransfer)" {
	rm -f /tmp/transient-folder-snapshot.log

	echo '#!/bin/bash' > "$tmpbindir"/rsync
	echo 'echo "rsync $@" >> /tmp/transient-folder-snapshot.log' >> "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view \
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
@test "transient-folder-view: snapshot rsync error handling" {
	rm -f /tmp/transient-folder-snapshot.log

	{
		echo '#!/bin/bash'
		echo 'echo "rsync $@" >> /tmp/transient-folder-snapshot.log'
		echo 'echo "rsync error" >&2'
		echo 'exit 42'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view --verbose "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view --debug "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run cat /tmp/transient-folder-snapshot.log
	rm -f /tmp/transient-folder-snapshot.log
	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ /.*\ /.*\ --progress ]]
}
@test "transient-folder-view: mount error handling" {
	function MOCK_MOUNT {
		echo '#!/bin/bash' > "$tmpbindir"/mount
		if [ "$1" == "rbind" ]; then
			echo 'if [[ "$@" =~ --rbind ]]; then echo "Bind mount fail"; exit 1; fi' >> "$tmpbindir"/mount
		elif [ "$1" == "tmpfs" ]; then
			echo 'if [[ "$@" =~ tmpfs ]]; then echo "tmpfs mount fail"; exit 1; fi' >> "$tmpbindir"/mount
		fi
		echo 'exec /usr/bin/mount "$@"' >> "$tmpbindir"/mount
		chmod +x "$tmpbindir"/mount
	}

	MOCK_MOUNT rbind
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[ "$output" == "Error: mount --rbind failed: Bind mount fail" ]

	MOCK_MOUNT rbind
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[ "$output" == "Error: mount --rbind failed: Bind mount fail" ]

	MOCK_MOUNT tmpfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[[ "$output" =~ ^Error:\ Mounting\ tmpfs\ to\ \"/.*\":\ tmpfs\ mount\ fail$ ]]
}
@test "transient-folder-view: Snapshot --debug" {
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,snapshot" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ rsync\ -.*\ --progress ]]
	# to-chk is included in rsync --progress, thus check for that
	[[ "$output" =~ to-chk ]]
}
@test "transient-folder-view: Prepends -- to unshare call" {
	{
		echo '#!/bin/bash'
		# shellcheck disable=SC2016
		echo '[ "$1" == "--help" ] && echo "This unshare supports --map-user!" && exit'
		# shellcheck disable=SC2016
		echo '[ "${*:5}" == "-- command and args" ] && echo True && exit'
		# shellcheck disable=SC2016
		echo 'exec "'"$(command -v unshare)"'" "$@"'
	} > "$tmpbindir"/unshare
	chmod +x "$tmpbindir"/unshare

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- command and args
	[ "$status" -eq 0 ]
	[ "$output" == "True" ]
}
@test "transient-folder-view: Drops -- from command" {
	# unshare that signals that we can't use --map-user
	{
		echo '#!/bin/bash'
		# shellcheck disable=SC2016
		echo '[ "$1" == "--help" ] && exit'
		# shellcheck disable=SC2016
		echo 'exec "'"$(command -v unshare)"'" "$@"'
	} > "$tmpbindir"/unshare
	chmod +x "$tmpbindir"/unshare

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- echo 1
	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
}
@test "transient-folder-view: snapshot with toleratepartialtransfer" {
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,toleratepartialtransfer" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]
}
@test "transient-folder-view: Overlay --debug" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ fuse-overlayfs\ -o\ lowerdir=.+\ -o\ upperdir=.+\ $tmpdir ]]
}
@test "transient-folder-view: Overlay multiple folders" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo -n "old" > "$tmpdir/a"
	mkdir "$tmpbindir/subfolder"
	echo "0" > "$tmpbindir/subfolder/file"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" "$tmpbindir,overlay" -- sh -c \
		"echo -n new > $tmpdir/a; echo 1 > $tmpbindir/subfolder/file; cat $tmpdir/a $tmpbindir/subfolder/file"
	[ "$status" -eq 0 ]
	[[ "$output" == "new1" ]]
	[ "$(cat "$tmpdir"/a "$tmpbindir"/subfolder/file)" == 'old0' ]
}
@test "transient-folder-view: Overlay folder with spaces" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	mkdir "$tmpdir/a folder with spaces"
	echo 0 > "$tmpdir/a folder with spaces/a file"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir/a folder with spaces,overlay" -- sh -c \
		"echo 1 > $tmpdir'/a folder with spaces/a file'; cat $tmpdir'/a folder with spaces/a file'"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	[ "$(cat "$tmpdir/a folder with spaces/a file")" == '0' ]
}
@test "transient-folder-view: Overlay folder with new lines" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	local DIRNAME="$tmpdir/a folder with a "$'\n'"new line"
	mkdir "$DIRNAME"
	echo 0 > "$DIRNAME/file"

	run "$BATS_TEST_DIRNAME"/transient-folder-view "$DIRNAME,overlay" -- sh -c \
		"cat \"$DIRNAME\"/file; echo 1 > \"$DIRNAME\"/file; cat \"$DIRNAME\"/file;"

	[ "$status" -eq 0 ]
	[[ "$output" == "0"$'\n'"1" ]]

	[ "$(cat "$DIRNAME/file")" == '0' ]
}
@test "transient-folder-view: overlay with nopreservegroup and nopreserveowner" {
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

	run "$BATS_TEST_DIRNAME"/transient-folder-view /etc,overlay -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-view /etc,overlay,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-view /etc,overlay,nopreservegroup -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-folder-view /etc,overlay,nopreservegroup,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$GID" ]]
}
@test "transient-folder-view: fuse-overlayfs error handling" {
	{
		echo '#!/bin/bash'
		echo 'exit 42'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-folder-view "$tmpdir,overlay" -- true
	[[ "$output" == "Error: Mounting fuse-overlayfs failed." ]]
}
