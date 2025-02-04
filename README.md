# chroot_manager

**chroot_manager** is a fully featured tool for managing chroot environments on Debian‐based systems. It provides a simple command-line interface for creating, connecting to, disconnecting from, and monitoring a chroot jail. The tool supports daemon mode—using `strace`—to log all system calls made within the chroot environment, along with installation and uninstallation support for easy deployment.

## Features

- **Create** a minimal Debian chroot jail using `debootstrap`.
- **Connect** to the chroot, automatically mounting necessary filesystems (e.g., `/dev`, `/proc`, `/sys`, `/tmp`).
- **Daemon mode:** With the `--daemon` flag, run the chroot session under `strace` so that all system calls (and those of forked child processes) are logged to separate files.
- **Disconnect** from the chroot and unmount all bind mounts.
- **Status** command to display the current mount status for the chroot jail.
- **Verbose/debug mode** for detailed logging.
- **Install/Uninstall:** Easily install the tool (and its man page and bash completions) to system directories.
- **Extensible:** Designed to be further enhanced with configuration file support, advanced logging, and additional completions.

## Requirements

- A Debian-based system.
- Root privileges are required for creating, connecting, disconnecting, and installing/uninstalling the tool.
- Required commands: `debootstrap`, `chroot`, `mount`, `xhost`, `xauth`, `sudo`, and `strace`.

## Installation

To install **chroot_manager** system-wide, run:

```bash
sudo ./chroot_manager.sh install [--verbose]
```

This command will:
- Copy the script to `/usr/local/bin/chroot_manager` and set the executable permission.
- Install the man page (if `chroot_manager.1` exists in the current directory) to `/usr/local/share/man/man1` and compress it.
- Install the bash completion file (if `chroot_manager.bash_completion` exists) to `/etc/bash_completion.d/chroot_manager`.

## Uninstallation

To remove **chroot_manager** and its associated files, run:

```bash
sudo ./chroot_manager.sh uninstall [--verbose]
```

This command removes:
- The binary from `/usr/local/bin/chroot_manager`.
- The man page from `/usr/local/share/man/man1/chroot_manager.1.gz`.
- The bash completion file from `/etc/bash_completion.d/chroot_manager`.

## Usage

**Basic Syntax:**

```bash
sudo chroot_manager [--verbose] [--daemon] <command>
```

**Commands:**

- **create**  
  Create the chroot jail using debootstrap.  
  Example:
  ```bash
  sudo chroot_manager create
  ```

- **connect**  
  Mount necessary filesystems, set up X access, and enter the chroot environment.  
  With `--daemon`, the session is traced via `strace`, and system calls are logged to files in the daemon log directory (default: `$(pwd)/chroot_daemon_logs`).  
  Example:
  ```bash
  sudo chroot_manager --daemon connect
  ```

- **disconnect**  
  Unmount the bind mounts from the chroot and revoke X server permissions.  
  Example:
  ```bash
  sudo chroot_manager disconnect
  ```

- **status**  
  Display the current mount status for the chroot jail.  
  Example:
  ```bash
  sudo chroot_manager status
  ```

- **help**  
  Display a detailed help message with usage and command descriptions.  
  Example:
  ```bash
  sudo chroot_manager help
  ```

- **install**  
  Install the tool to `/usr/local/bin` along with its man page and bash completion.  
  Example:
  ```bash
  sudo chroot_manager install
  ```

- **uninstall**  
  Remove the installed tool and its associated files.  
  Example:
  ```bash
  sudo chroot_manager uninstall
  ```

## Configuration

By default, **chroot_manager** assumes:
- The chroot jail is located at `/var/chroot`.
- The Debian mirror used is `http://deb.debian.org/debian`.
- Daemon logs (when in daemon mode) are stored in a directory in the current working directory named `chroot_daemon_logs`.

Feel free to modify these defaults directly in the script or extend the tool with configuration file support in future versions.

## Bash Completion

If installed, bash completions will allow you to auto-complete the available commands and options when using **chroot_manager** in your shell.

## License

This project is released under the terms of the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions, suggestions, and bug reports are welcome! Please submit issues and pull requests via GitHub.

## Author

*Kleinpanic*  
*kleinpanic@gmail.com*

