# Transient File View
Create transient views of directories in a user namespace. This creates a new mount namespace with transient versions of the given files or directories.

For directories these views are either temporary snapshots ("snapshot") created by tar-ing the folder content into a tmpfs mount, or overlays ("overlay") created by [fuse-overlayfs](https://github.com/containers/fuse-overlayfs).

This can, for example, be used to run tests against older versions of a software, without having to actually check out the old version, or for safely running experimental versions of a software with actual user data.

### Usage

```
Usage: transient-file-view [--help] [--verbose|--debug] file [file]* [-- command [ARG]...]

Create transient views of files or directories in a user namespace. This creates a new mount namespace with
transient versions of the given files or directories.
For directories these views are either temporary snapshots ("snapshot") created by tar-ing the folder content
into a tmpfs mount, or overlays ("overlay") created by fuse-overlayfs.

        --help                  Show this help
        --verbose               Print verbose debugging info
        --debug                 Show all debug information (implies --verbose)
        file                    file or directory to create a view of
        command                 if command is omitted an interactive shell will be launched

Files or directories can be given using the following syntax:
        path/of/the/file[,snapshot][,overlay][,toleratepartialtransfer][,exclude=PATTERN]*

for directories only:
        "snapshot" to create a tmporary snapshot of the directory in a new tmpfs (mutually exclusive with "overlay").
        "overlay" to use fuse-overlayfs for the directory view (mutually exclusive with "snapshot").
directory "snapshot" mode only:
        "exclude" PATTERN is passed to "tar" to determine which files not to sync into the snapshot.
                (tar --exclude), can be given multiple times.
        "toleratepartialtransfer" if set, don't fail on partial transfers (tar --ignore-failed-read).
```

### Example
```
$ pwd
/tmp/tmp.ZWMB8NHI9M
$ echo 1 > foo
$ transient-file-view . -- sh -i
sh-5.1$ pwd
/tmp/tmp.ZWMB8NHI9M
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
