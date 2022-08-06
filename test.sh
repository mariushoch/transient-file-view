#!/bin/sh

set -e

shellcheck transient-file-view transient-file-view.bats
bats transient-file-view.bats
if bwrap --ro-bind / / true 2>/dev/null && test -w /dev/fuse && test -c /dev/fuse; then
	# Run the tests without working fuse as well.
	echo 'Re-running tests without access to "/dev/fuse".'
	bwrap --dev-bind / / --ro-bind /etc/hostname /dev/fuse bats transient-file-view.bats
fi

echo Success
