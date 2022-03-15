#!/bin/sh

set -e

shellcheck transient-folder-view transient-folder-view.bats
bats transient-folder-view.bats

echo Success
