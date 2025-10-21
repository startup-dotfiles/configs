# Dotfiles -- configs

Configuration files scattered across various locations.

## Usage

Use `./deploy.sh` to install files from this repository into the specified locations under $HOME according to the rules in `MANIFEST.linux`.
Of course, the script automatically backs up files to the backup directory before installing.
You can choose to install files by `copy` or `symlink`; see [MANIFEST.linux](./MANIFEST.linux) for details.

```sh
# The script provides several options.
./deploy.sh                 # Install them into your $HOME
./deploy.sh -h              # only offer help info
./deploy.sh -f              # force write (with backup)
./deploy.sh -m <MANIFEST>   # specify a manifest file
```

## References

- [A script from rexim's dotfiles](https://github.com/rexim/dotfiles/blob/master/deploy.sh)
