# Install asdf from the GitHub release tarball, not via the package manager

Every other tool in this repo installs through `install_from_pm`, so a future contributor will look at `asdf/install_asdf.sh` downloading a tarball and ask why it deviates. The reason: asdf's officially supported package managers are Homebrew, Zypper, and Pacman, none of which intersect the distros this repo currently targets (Debian/Ubuntu family). On `apt`, the `asdf` package is an unrelated Advanced Spectral Data Format library — installing it would be actively wrong. The release tarball from `github.com/asdf-vm/asdf/releases` is the only path upstream endorses that works across every host we support today.

When this repo grows to support brew/zypper/pacman hosts, the PM path becomes a viable additional branch alongside the tarball — not a replacement for it.
