# Transient Folder Snapshot
Make a transient snapshot of a directory in a user namespace. This creates a new mount namespace, mounts tmpfs over the given directories and rsyncs the original directory content into the new (temporary) mounts.

This can, for example, be used to run tests against older versions of a software, without having to actually check out the old version, or for running experimental versions of a software with the actual user configuration.

### Usage

```
Usage: transient-folder-snapshot [--help] [--verbose|--debug] directory [directory]* -- command

Make a transient snapshot of a directory in a user namespace. This creates a new mount namespace, mounts tmpfs
over the given directories and rsyncs the original directory content into the new (temporary) mounts.

        --help                  Show this help
        --verbose               Print verbose debugging info
        --debug                 Show all debug information (implies --verbose)
        directory               directories to be snapshotted

Directories can be given using the following syntax:
        path/of/the/directory[,nopreserveowner][,nopreservegroup][,exclude=PATTERN]*
        "exclude" PATTERN is passed to "rsync" to determine which files not to sync into the snapshot
                (rsync --exclude), can be given multiple times.
        "nopreserveowner" can be used to instruct rsync to not preserve file ownership (don't pass rsync -o).
        "nopreservegroup" can be used to instruct rsync to not preserve file group (don't pass rsync -g).
```

### Example
```
$ echo 1 > foo
$ transient-folder-snapshot . -- sh -i
$ cat foo
1
$ rm foo
$ cat foo
cat: foo: No such file or directory
$ exit
$ cat foo
1
```
