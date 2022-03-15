# Transient Folder View
Create transient views of directories in a user namespace. This creates a new mount namespace where we will create transient versions of the given directories and mount them over the original directories.

These views are either temporary snapshots ("snapshot") created by rsync-ing the folder content into a tmpfs mount, or overlays ("overlay") created by fuse-overlayfs.

This can, for example, be used to run tests against older versions of a software, without having to actually check out the old version, or for running experimental versions of a software with the actual user configuration.

### Usage

```
Usage: transient-folder-view [--help] [overlay|snapshot] [--verbose|--debug] directory [directory]* [-- command [ARG]...]

Create transient views of directories in a user namespace. This creates a new mount namespace where
we will create transient versions of the given directories.

These views are either temporary snapshots ("snapshot") created by rsync-ing the folder content
into a tmpfs mount, or overlays ("overlay") created by fuse-overlayfs.

        --help                  Show this help
        --verbose               Print verbose debugging info
        --debug                 Show all debug information (implies --verbose)
        directory               directories to be snapshotted
        command                 if command is omitted an interactive shell will be launched

Directories can be given using the following syntax:
        path/of/the/directory[,nopreserveowner][,nopreservegroup][,toleratepartialtransfer][,exclude=PATTERN]*
        "nopreserveowner" to not preserve file ownership (don't pass rsync -o or use fuse-overlayfs -o squash_to_uid).
        "nopreservegroup" to not preserve file group (don't pass rsync -g or use fuse-overlayfs -o squash_to_gid).

        The following options apply only to snapshot mode:
        "exclude" PATTERN is passed to "rsync" to determine which files not to sync into the snapshot
                (rsync --exclude), can be given multiple times.
        "toleratepartialtransfer" if set, don't fail on partial transfer errors (exit code 23/24 from rsync).
```

Alternatively `transient-folder-snapshot` and `transient-folder-overlay` can be used for directly accessing the "snapshot" or "overlay" mode respectively.

### Example
```
$ pwd
/tmp/tmp.3N56P6bMiW
$ echo 1 > foo
$ transient-folder-snapshot . -- sh -i
sh-5.1$ pwd
/tmp/tmp.3N56P6bMiW
sh-5.1$ cat foo
1
sh-5.1$ rm foo
sh-5.1$ cat foo
cat: foo: No such file or directory
sh-5.1$ exit
exit
$ cat foo
1

```
