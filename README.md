# Dotfiles -- configs

Configuration files scattered across various locations.

## Usage

Use `./deploy.sh` to install files from this repository into the specified locations under `$HOME` according to the rules in `MANIFEST.linux`.
Of course, the script automatically backs up files to the backup directory before installing.
You can choose to install files by `copy` or `symlink`; see [MANIFEST.linux](./MANIFEST.linux) for details.

```sh
# The script provides several options.
./deploy.sh                   # Install them into your $HOME
./deploy.sh -h                # only offer help info
./deploy.sh -f                # force write (with backup)
./deploy.sh -m <MANIFEST>     # specify a manifest file
./deploy.sh -o <copy/symlink> # specify default operation: copy/symlink

```

> [!WARNING]
> `./deploy.sh` uses `MANIFEST.linux` by default, typically for a full deployment. If you only want to install part of it,
> refer to the files in the [recipes](./recipes/) directory I provided and use the `-m` option to specify a file.

> [!WARNING]
> `./deploy.sh` supports two deployment methods: `copy` or `symlink`. It parses the input MANIFEST file and uses the operation field
> of each valid entry to deploy the specified files or directories. This approach is flexible: you can control each file and
> directory individually, deploying some with `copy` and others with `symlink`.
> If you want to use a single deployment method for all entries, run the script with the `-o copy` or `-o symlink` option;
> this will override and ignore the operation field for all entries in the MANIFEST file.

> [!NOTE]
> Tip: You can run `./deploy.sh -f` to make a backup; it will save the previous state before you modify local files.

## Packages

```sh
# [Arch Linux] Install packages from a list
# See https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Install_packages_from_a_list
# NOTE: This will filter out external packages from the list that come from the AUR or are installed locally.
pacman -S --needed $(comm -12 <(pacman -Slq | sort) <(sort pkglist.txt))
# Then, install packages from the AUR using yay.
yay -S --needed - < pkglist-aur.txt
```

## Troubleshooting

### Unknown operation xxx. Skipping

Each valid MANIFEST entry must include at least two fields: `file_or_dir` and `destination`. Because the operation field sits between these two, the script will still parse that field even if you specify a default operation with the `-o` option. Therefore you must either set the operation field to "copy" or "symlink", or leave it empty.

```txt
# For example
## Incorrent:
appsps/coding/.clangd|.config/clangd|config.yaml     # Unknown operation .config/clangd
appsps/coding/.clangd|???|.config/clangd|config.yaml # Unknown operation ???.

## Corrent:
apps/coding/.clangd|copy|.config/clangd|config.yaml
apps/coding/.clangd|symlink|.config/clangd|config.yaml
apps/coding/.clangd||.config/clangd|config.yaml         # Use -o option
```

### Sync with copying

For files or directories deployed via symlink, synchronization with the repository happens automatically. For those deployed via copy, if you want to sync locally modified files back to the repository, use the `sync_copy.sh` script. Its usage is very similar to `deploy.sh`, except the direction of deployment is reversed.

### Migration

If you want to create your own repository to manage `$HOME` directory, download the two scripts ([deploy.sh](./deploy.sh) and [sync_copy.sh](./sync_copy.sh)), use [MANIFEST.linux](./MANIFEST.linux) as a reference to write your own manifest, and update the default MANIFEST variable in the scripts. To initialize the repository, run `sync_copy.sh` to copy the files or directories from your local `$HOME` that you want to manage into the repository. To manage files via symlinks or deploy your config files to other machines, run `deploy.sh`. In short: use `sync_copy.sh` for regular maintenance, and `deploy.sh` to deploy configurations to other machines.

## References

- [A script from rexim's dotfiles](https://github.com/rexim/dotfiles/blob/master/deploy.sh)
