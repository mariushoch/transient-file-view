#!/bin/sh

set -e

shellcheck transient-folder-snapshot transient-folder-snapshot.bats
bats transient-folder-snapshot.bats

echo Success
