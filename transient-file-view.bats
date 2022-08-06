#!/usr/bin/env bats

can_use_fuse_overlayfs=""
if command -v fuse-overlayfs >/dev/null && test -c /dev/fuse -a -w /dev/fuse && [[ "$(lsmod)" =~ fuse\  ]]; then
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

# Like run, but compares the output/ exit code to that
# of the previous run.
function runAssertSameAsLast {
	local old_output="$output"
	local old_status="$status"

	run "$@"

	[ "$old_output" == "$output" ] || (echo "runAssertSameAsLast: Output mismatch"; false)
	[ "$old_status" == "$status" ] || (echo "runAssertSameAsLast: Status mismatch"; false)
}

@test "transient-file-view --help" {
	run "$BATS_TEST_DIRNAME"/transient-file-view --help
	[ "$status" -eq 0 ]

	[[ "$output" =~ Usage:\ transient-file-view ]]
	[[ "$output" =~ toleratepartialtransfer ]]
	[[ "$output" =~ if\ set,\ don\'t\ fail\ on ]]
}
@test "transient-file-view: Too few parameters" {
	run "$BATS_TEST_DIRNAME"/transient-file-view

	[[ "$output" =~ Error:\ Expected\ at\ least ]]
	[[ "$output" =~ Usage:\ transient-file-view ]]
	[ "$status" -eq 1 ]
}
@test "transient-file-view: Directory" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030
	if [ -n "$can_use_fuse_overlayfs" ]; then
		runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	fi
	runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
}
@test "transient-file-view: File" {
	# File "a" is transient, file "b" isn't.
	echo 0 > "$tmpdir"/a
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/a" -- sh -c "echo 1 > $tmpdir/a; echo 2 > $tmpdir/b; cat $tmpdir/a"

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ "$(cat "$tmpdir"/a)" == "0" ]
	[ "$(cat "$tmpdir"/b)" == "2" ]
}
@test "transient-file-view: File debug" {
	echo 0 > "$tmpdir"/FILENAME
	run "$BATS_TEST_DIRNAME"/transient-file-view --debug "$tmpdir/FILENAME" -- true

	[ "$status" -eq 0 ]
	[[ "$output" =~ Acting\ on\ file\ \".*\/FILENAME\"\.$ ]]
}
@test "transient-file-view: File - cat failure" {
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/cat
	chmod +x "$tmpbindir"/cat
	echo 0 > "$tmpdir"/FILENAME
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/FILENAME" -- true

	[ "$status" -ne 0 ]
	[[ "$output" =~ ^Error:\ Copying\ contents\ of\ \".*\/FILENAME\"\ to\ \".*\"\.$ ]]
}
@test "transient-file-view: File - mount failure" {
	{
		echo '#!/bin/bash'
		echo 'if [[ "$@" =~ --bind ]]; then echo "MOUNT-ERROR"; exit 1; fi'
		echo 'exec /usr/bin/mount "$@"'
	} > "$tmpbindir"/mount
	chmod +x "$tmpbindir"/mount

	echo 0 > "$tmpdir"/FILENAME
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/FILENAME" -- true

	[ "$status" -ne 0 ]
	[[ "$output" =~ ^Error:\ Mounting\ \".*\"\ to\ \".*\/FILENAME\":\ \"MOUNT-ERROR\"\.$ ]]
}
@test "transient-file-view: snapshot" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "tmpfs" ]
}
@test "transient-file-view: No leftovers in /tmp" {
	tmp="$(dirname "$(mktemp -u --tmpdir -d)")"
	tmpFilesPrior="$(find "$tmp" -maxdepth 1 -name '*transient--view*' 2>/dev/null | wc -l)"

	# snapshot success
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	# We don't allow working on /dev
	run "$BATS_TEST_DIRNAME"/transient-file-view '/dev' -- true
	[ "$status" -gt 0 ]

	# We don't allow working on /tmp
	run "$BATS_TEST_DIRNAME"/transient-file-view /tmp -- true
	[ "$status" -gt 0 ]

	# Make rsync fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view --debug "$tmpdir,snapshot" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/rsync

	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		# overlay success
		run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" -- true
		[ "$status" -eq 0 ]
		[ "$output" == "" ]
	fi

	# Make fuse-overlayfs fail
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view --debug "$tmpdir,overlay" -- true
	[ "$status" -gt 0 ]
	rm "$tmpbindir"/fuse-overlayfs

	tmpFilesNow="$(find "$tmp" -maxdepth 1 -name '*transient-file-view*' 2>/dev/null | wc -l)"
	[ "$tmpFilesPrior" -eq "$tmpFilesNow" ]
}
@test "transient-file-view: overlay" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" -- findmnt --noheadings -o FSTYPE "$tmpdir"

	[ "$status" -eq 0 ]
	[ "$output" == "fuse.fuse-overlayfs" ]
}
@test "transient-file-view: Invalid directory options" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,nopreservegroup,snapshot,banana,exclude=foo,exclude=bar," -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-file-view --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,exclude=.git,nopreservegroup,banana,nopreserveowner" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-file-view --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot,nopreservegroup,nopreserveuser" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-file-view --help\"." ]

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay,nopreservegroup,nopreserveuser" -- true
	[ "$status" -ne 0 ]
	[ "$output" == "Error: Invalid directory format, please refer to \"transient-file-view --help\"." ]
}
@test "transient-file-view: Empty exclude" {
	echo 4 > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,exclude=,exclude=,nopreservegroup" -- cat "$tmpdir/a"
	[ "$status" -eq 0 ]
	[ "$output" == "4" ]
	runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot,exclude=,exclude=,nopreservegroup" -- cat "$tmpdir/a"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay,exclude=,exclude=,nopreservegroup" -- cat "$tmpdir/a"
	fi
}
@test "transient-file-view: Non-existent folder" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" /does-not-exist -- true
	runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" /does-not-exist,overlay -- true
	runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" /does-not-exist,snapshot -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot act on \"/does-not-exist\": No such file or directory" ]
}
@test "transient-file-view: Exit code" {
	maybeOverlay=",overlay"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		maybeOverlay=""
	fi

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir$maybeOverlay" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]

	mkdir "$tmpdir/a" "$tmpdir/b"
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/a$maybeOverlay" "$tmpdir/b" -- sh -c 'exit 123'
	[ "$status" -eq 123 ]
	[ "$output" == "" ]
}
@test "transient-file-view: Fails for /tmp" {
	run "$BATS_TEST_DIRNAME"/transient-file-view /tmp// -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
	run "$BATS_TEST_DIRNAME"/transient-file-view /tmp//,overlay -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /tmp (as the tool makes internal use ot it)." ]
}
@test "transient-file-view: Fails for /dev" {
	run "$BATS_TEST_DIRNAME"/transient-file-view /dev -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /dev." ]
}
@test "transient-file-view: Fails for /" {
	run "$BATS_TEST_DIRNAME"/transient-file-view /./ -- true
	[ "$status" -eq 1 ]
	[ "$output" == "Error: Cannot work on /." ]
}
@test "transient-file-view: Trailing slash" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/,snapshot" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir/,overlay" -- sh -c "echo 1 > $tmpdir/a; cat $tmpdir/a"
	fi

	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
	[ ! -f "$tmpdir/a" ]
}
@test "transient-file-view: Folder with spaces" {
	mkdir -p /tmp/"transient folder snapshot test"

	run "$BATS_TEST_DIRNAME"/transient-file-view /tmp/"transient folder snapshot test,snapshot" -- \
		sh -c 'cd /tmp/"transient folder snapshot test"; echo CONTENT > a; cat a'
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view /tmp/"transient folder snapshot test,overlay" -- \
			sh -c 'cd /tmp/"transient folder snapshot test"; echo CONTENT > a; cat a'
	fi
	[ "$status" -eq 0 ]
	[ "$output" == "CONTENT" ]
	[ ! -f /tmp/"transient folder snapshot test"/a ]

	rm -rf /tmp/"transient folder snapshot test"
}
@test "transient-file-view: Folder with new lines" {
	DIRNAME="$(echo -e "/tmp/transient folder snapshot\ntest/")"
	mkdir -p "$DIRNAME"
	echo EXCLUDED > "$DIRNAME/stuff"
	echo -n a > "$DIRNAME/CONTENT"

	# shellcheck disable=SC2016
	run "$BATS_TEST_DIRNAME"/transient-file-view "$DIRNAME,snapshot,exclude=stuff" -- \
		sh -c 'cd "$1"; echo -n b >> CONTENT; cat *' -- "$DIRNAME"
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		# Note: This is slightly different, as overlay does not support exclude
		# shellcheck disable=SC2016
		runAssertSameAsLast "$BATS_TEST_DIRNAME"/transient-file-view "$DIRNAME,overlay" -- \
			sh -c 'cd "$1"; echo -n b >> CONTENT; cat CONTENT' -- "$DIRNAME"
	fi
	[ "$status" -eq 0 ]
	[ "$output" == "ab" ]
	[ "$(cat "$DIRNAME/CONTENT")" == "a" ]

	rm -rf "$DIRNAME"
}
@test "transient-file-view: Multiple folders" {
	mkdir -p "$tmpdir"/dirA "$tmpdir"/dirB

	echo SHOULD_NOT_GET_EXCLUDED > "$tmpdir"/dirA/file.large
	echo 1 > "$tmpdir"/dirB/file.small
	echo 2 > "$tmpdir"/dirB/file.large
	echo blah > "$tmpdir"/dirB/blah

	# This should not affect the real copy of these files
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir"/dirA "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
		find "$tmpdir"/* -type f -delete
	[ "$status" -eq 0 ]
	[ "$output" == "" ]

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir"/dirA "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
		find "$tmpdir"/
	[ "$status" -eq 0 ]

	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -n "$can_use_fuse_overlayfs" ]; then
		run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir"/dirA,overlay "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
			find "$tmpdir"/* -type f -delete
		[ "$status" -eq 0 ]
		[ "$output" == "" ]

		run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir"/dirA,overlay "$tmpdir"/dirB,exclude=blah,exclude=*.large --\
			find "$tmpdir"/
		[ "$status" -eq 0 ]
	fi

	[[ "$output" =~ "$tmpdir"/dirA/file.large ]]
	# Excluded files
	[[ ! "$output" =~ "$tmpdir"/dirB/file.large ]]
	[[ ! "$output" =~ "$tmpdir"/dirB/blah ]]
}
@test "transient-file-view: Fails nicely if wrapping fails" {
	run sh -c 'cat '"$BATS_TEST_DIRNAME"'/transient-file-view | bash /dev/stdin -- . -- true'
	[ "$output" == "Error: Could not locate own location (needed for wrapped execution)." ]
	[ "$status" -eq 255 ]
}
@test "transient-file-view: Map user/gid" {
	if [[ ! "$(unshare --help)" =~ --map-user ]]; then
		# Needs unshare with --map-user/--map-group support.
		skip
	fi

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- id -u
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -u)" ]
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- id -g
	[ "$status" -eq 0 ]
	[ "$output" == "$(id -g)" ]
}
@test "transient-file-view: Snapshot argument parsing (exclude, nopreservegroup, nopreserveowner and toleratepartialtransfer)" {
	rm -f /tmp/transient-folder-snapshot.log

	echo '#!/bin/bash' > "$tmpbindir"/rsync
	echo 'echo "rsync $@" >> /tmp/transient-folder-snapshot.log' >> "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view \
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
@test "transient-file-view: snapshot rsync error handling" {
	rm -f /tmp/transient-folder-snapshot.log

	{
		echo '#!/bin/bash'
		echo 'echo "rsync $@" >> /tmp/transient-file-snapshot.log'
		echo 'echo "rsync error" >&2'
		echo 'exit 42'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view --verbose "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view --debug "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[[ "$output" =~ rsync\ error ]]
	[[ "$output" =~ Error:\ rsync\ to\ create\ the\ snapshot\ failed\. ]]

	run cat /tmp/transient-file-snapshot.log
	rm -f /tmp/transient-file-snapshot.log
	[[ "${lines[0]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[1]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ / ]]
	[[ "${lines[2]}" =~ ^rsync\ -rlptD\ --checksum-choice=none\ -g\ -o\ /.*\ /.*\ --progress ]]
}
@test "transient-file-view: mount error handling" {
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
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[ "$output" == "Error: mount --rbind failed: Bind mount fail" ]

	MOCK_MOUNT rbind
	runAssertSameAsLast env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" -- touch /tmp/a

	MOCK_MOUNT tmpfs
	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- touch /tmp/a
	[ "$status" -eq 255 ]
	[[ "$output" =~ ^Error:\ Mounting\ tmpfs\ to\ \"/.*\":\ tmpfs\ mount\ fail$ ]]
}
@test "transient-file-view: Snapshot --debug" {
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,snapshot" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ rsync\ -.*\ --progress ]]
	# to-chk is included in rsync --progress, thus check for that
	[[ "$output" =~ to-chk ]]
}
@test "transient-file-view: Prepends -- to unshare call" {
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

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- command and args
	[ "$status" -eq 0 ]
	[ "$output" == "True" ]
}
@test "transient-file-view: Drops -- from command" {
	# unshare that signals that we can't use --map-user
	{
		echo '#!/bin/bash'
		# shellcheck disable=SC2016
		echo '[ "$1" == "--help" ] && exit'
		# shellcheck disable=SC2016
		echo 'exec "'"$(command -v unshare)"'" "$@"'
	} > "$tmpbindir"/unshare
	chmod +x "$tmpbindir"/unshare

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- echo 1
	[ "$status" -eq 0 ]
	[ "$output" == "1" ]
}
@test "transient-file-view: snapshot with toleratepartialtransfer" {
	{
		echo '#!/bin/bash'
		echo 'exit 23'
	} > "$tmpbindir"/rsync
	chmod +x "$tmpbindir"/rsync

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir" -- true
	[ "$status" -eq 255 ]
	[ "$output" == "Error: rsync to create the snapshot failed." ]

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,toleratepartialtransfer" -- true
	[ "$status" -eq 0 ]
	[ "$output" == "" ]
}
@test "transient-file-view: Overlay --debug" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo "HEY" > "$tmpdir/a"

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" --debug -- sh -c "cat $tmpdir/a"
	[ "$status" -eq 0 ]
	[[ "$output" =~ HEY ]]
	echo "$output" | grep -qF "Acting on folder \"$tmpdir\"."
	[[ "$output" =~ Running:\ fuse-overlayfs\ -o\ lowerdir=.+\ -o\ upperdir=.+\ $tmpdir ]]
}
@test "transient-file-view: Overlay multiple folders" {
	# Workaround for a shellcheck 0.7.2 bug
	# shellcheck disable=SC2030,SC2031
	if [ -z "$can_use_fuse_overlayfs" ]; then
		skip
	fi
	echo -n "old" > "$tmpdir/a"
	mkdir "$tmpbindir/subfolder"
	echo "0" > "$tmpbindir/subfolder/file"

	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" "$tmpbindir,overlay" -- sh -c \
		"echo -n new > $tmpdir/a; echo 1 > $tmpbindir/subfolder/file; cat $tmpdir/a $tmpbindir/subfolder/file"
	[ "$status" -eq 0 ]
	[[ "$output" == "new1" ]]
	[ "$(cat "$tmpdir"/a "$tmpbindir"/subfolder/file)" == 'old0' ]
}
@test "transient-file-view: Overlay with nopreservegroup and nopreserveowner" {
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

	run "$BATS_TEST_DIRNAME"/transient-file-view /etc,overlay -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-file-view /etc,overlay,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$NB_GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-file-view /etc,overlay,nopreservegroup -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$NB_UID-$GID" ]]

	run "$BATS_TEST_DIRNAME"/transient-file-view /etc,overlay,nopreservegroup,nopreserveowner -- stat --printf %u-%g /etc/hostname
	[ "$status" -eq 0 ]
	[[ "$output" == "$UID-$GID" ]]
}
@test "transient-file-view: Overlay fuse-overlayfs error handling" {
	{
		echo '#!/bin/bash'
		echo 'exit 42'
	} > "$tmpbindir"/fuse-overlayfs
	chmod +x "$tmpbindir"/fuse-overlayfs

	run env PATH="$tmpbindir:$PATH" "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay" -- true
	[[ "$output" == "Error: Mounting fuse-overlayfs failed." ]]
}
@test "transient-file-view: Overlay and snapshot are mutually exclusive" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay,snapshot" -- true
	[ "$status" -ne 0 ]
	[[ "$output" == "Options \"snapshot\" and \"overlay\" are mutually exclusive." ]]
}
@test "transient-file-view: Overlay does not allow exclude" {
	run "$BATS_TEST_DIRNAME"/transient-file-view "$tmpdir,overlay,exclude=blah" -- true
	[ "$status" -ne 0 ]
	[[ "$output" == "Error: overlay does not support exclude." ]]
}
