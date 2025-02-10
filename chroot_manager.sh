#!/bin/bash
# chroot_manager.sh
#
# A fully featured chroot management tool with:
#   - A command-line interface (create, connect, disconnect, status, help, install, uninstall)
#   - Improved error handling and logging
#   - A verbose/debug mode (--verbose)
#   - A daemon mode (--daemon) which, when used with connect, will run
#     the chroot session under strace to log all activity (system calls) in separate files.
#
# Requirements:
#   - Some commands (create, connect, disconnect, install, uninstall) must be run as root.
#
# Usage:
#   sudo ./chroot_manager.sh [--verbose] [--daemon] <command>
#
# Commands:
#   create      Create the chroot jail using debootstrap.
#   connect     Mount necessary filesystems, set up X access, and enter the chroot.
#               With --daemon, the session is run under strace to log all activity.
#   disconnect  Unmount the filesystems from the chroot (if needed).
#   status      Display the current mount status for the chroot jail.
#   help        Display a detailed help message.
#   install     Install chroot_manager to /usr/local/bin (and install man page and shell completions).
#   uninstall   Uninstall chroot_manager and remove its man page and shell completions.
#
# Note:
#   By default, the script assumes the chroot jail is located at /var/chroot.
#   When using --daemon, the log files will be stored in a directory created in the
#   current working directory (default: "chroot_daemon_logs"). After the chroot session ends,
#   the script will attempt to rename each log file based on the traced program’s name (if available)
#   and ignore logs for trivial commands. Finally, the script will adjust ownership and permissions
#   on that directory and its contents so they are accessible to the invoking user.
#

# --- Global Variables and Defaults ---
CHROOT_DIR="/var/chroot"
DEBIAN_MIRROR="http://deb.debian.org/debian"
LOGFILE="/var/log/chroot_manager.log"
VERBOSE=0
DAEMON=0
# Default directory to store daemon logs
DAEMON_LOG_DIR="$(pwd)/chroot_daemon_logs"

# List of trivial commands to ignore in daemon logs (basename only)
IGNORE_LIST=(bash sh ls cat echo grep mount umount)

# If running as root via sudo (SUDO_USER is set) but the environment isn’t fully preserved,
# force a re-run with sudo -E. We use _ENV_PRESERVED as a marker to avoid an infinite loop.
if [ -n "$SUDO_USER" ] && [ -z "$_ENV_PRESERVED" ]; then
    echo "Forcing re‑exec with preserved environment variables..."
    export _ENV_PRESERVED=1
    exec sudo -E "$0" "$@"
fi

# --- Logging Functions ---
function log_info() {
    echo "[INFO] $(date +'%F %T') $*" | tee -a "$LOGFILE"
}

function log_debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[DEBUG] $(date +'%F %T') $*" | tee -a "$LOGFILE"
    else
        echo "[DEBUG] $(date +'%F %T') $*" >> "$LOGFILE"
    fi
}

function log_error() {
    echo "[ERROR] $(date +'%F %T') $*" | tee -a "$LOGFILE" >&2
}

# --- Extended Help Message ---
function help_message() {
    cat <<EOF
chroot_manager.sh - A chroot management tool

Usage:
   sudo $0 [--verbose] [--daemon] <command>

Commands:
   create
       Create the chroot jail using debootstrap.
       Sets up a minimal Debian environment in \$CHROOT_DIR.
       
   connect
       Mount necessary filesystems (dev, proc, sys, tmp) into the chroot,
       set up X access, and then enter the chroot environment.
       When the chroot session ends, the bind mounts are automatically cleaned up.
       With the --daemon flag, the session is launched under strace so that every system call
       from the chroot process and its children is logged. The logs are stored in a directory:
           \$DAEMON_LOG_DIR
       Each log file is post-processed to try to include the traced program's name (if found)
       and trivial commands are ignored. Finally, the log directory and its files will have their
       ownership and permissions changed so the invoking user (from \$SUDO_USER) can read and write them.
       
   disconnect
       Unmount the filesystems from the chroot.
       Checks if bind mounts exist for \$CHROOT_DIR and, if so, unmounts them.
       
   status
       Displays the current mount status for the chroot jail (\$CHROOT_DIR).
       
   install
       Installs chroot_manager to /usr/local/bin, and copies the man page and bash completion file
       (if found in the current directory) to the appropriate locations.
       
   uninstall
       Uninstalls chroot_manager from /usr/local/bin and removes the installed man page and bash completion file.
       
   help
       Display this detailed help message.

Options:
   --verbose
       Enable verbose/debug mode (more detailed logging to console and log file).
       
   --daemon
       When used with the 'connect' command, run the chroot session under strace in daemon mode,
       logging all system call activity in separate log files.
       
Notes:
   - Commands that modify the chroot environment (create, connect, disconnect, install, uninstall)
     must be run as root.
   - By default, the chroot jail is located at: \$CHROOT_DIR.
EOF
}

# --- Usage (Short) ---
function usage() {
    cat <<EOF
Usage: $0 [--verbose] [--daemon] <command>
Try '$0 help' for more information.
EOF
}

# --- Dependency Check ---
REQUIRED_CMDS=(debootstrap chroot mount xhost xauth sudo strace)
function check_dependencies() {
    local missing=0
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command '$cmd' is not installed."
            missing=1
        fi
    done
    if [ $missing -ne 0 ]; then
        exit 1
    fi
}

# --- Check for Chroot Jail Existence ---
function check_jail() {
    if [ ! -d "$CHROOT_DIR" ]; then
        log_error "Chroot jail '$CHROOT_DIR' does not exist."
        echo "Please create the chroot environment first using the 'create' command."
        exit 1
    fi
}

# --- Mount / Unmount Filesystems ---
function mount_filesystems() {
    local dirs=(dev proc sys tmp)
    for d in "${dirs[@]}"; do
        log_info "Mounting /$d to ${CHROOT_DIR}/$d..."
        if ! mountpoint -q "${CHROOT_DIR}/$d"; then
            if ! sudo mount --bind "/$d" "${CHROOT_DIR}/$d"; then
                log_error "Error mounting /$d"
                exit 1
            fi
        else
            log_debug "${CHROOT_DIR}/$d is already mounted."
        fi
    done

    # Mount devpts to ensure pseudo-terminal support.
    if ! mountpoint -q "${CHROOT_DIR}/dev/pts"; then
        log_info "Mounting devpts to ${CHROOT_DIR}/dev/pts..."
        if ! sudo mount -t devpts devpts "${CHROOT_DIR}/dev/pts"; then
            log_error "Error mounting devpts at ${CHROOT_DIR}/dev/pts"
            exit 1
        fi
    fi
}

function unmount_filesystems() {
    local dirs=(dev/pts dev proc sys tmp)
    local any_mounted=0
    for d in "${dirs[@]}"; do
        if mountpoint -q "${CHROOT_DIR}/$d"; then
            any_mounted=1
            log_info "Unmounting ${CHROOT_DIR}/$d..."
            if ! sudo umount "${CHROOT_DIR}/$d"; then
                log_error "Error unmounting ${CHROOT_DIR}/$d"
            fi
        else
            log_debug "${CHROOT_DIR}/$d is not mounted."
        fi
    done
    return $any_mounted
}

# --- Post-Process Daemon Logs ---
function post_process_daemon_logs() {
    log_info "Post-processing daemon logs in directory: $DAEMON_LOG_DIR"
    # Iterate over log files matching the pattern (they are created with suffix .<pid>)
    for logfile in "$DAEMON_LOG_DIR"/chroot_daemon.log.*; do
        [ -e "$logfile" ] || continue
        # Extract the PID from the filename: assume filename ends with .<pid>
        pid="${logfile##*.}"
        # Try to extract the first execve call to determine the program name.
        prog_full=$(grep -m 1 'execve(' "$logfile" | sed -E 's/.*execve\("([^"]+)".*/\1/')
        if [ -n "$prog_full" ]; then
            prog_name=$(basename "$prog_full")
        else
            prog_name="pid${pid}"
        fi

        # Check if the program is in the ignore list (compare only the basename)
        ignore=0
        for trivial in "${IGNORE_LIST[@]}"; do
            if [ "$prog_name" == "$trivial" ]; then
                ignore=1
                break
            fi
        done

        if [ "$ignore" -eq 1 ]; then
            log_debug "Ignoring trivial log for program '$prog_name' (file: $logfile). Removing."
            rm -f "$logfile"
        else
            newname="$DAEMON_LOG_DIR/${prog_name}_${pid}.log"
            log_info "Renaming log file '$logfile' to '$newname'"
            mv "$logfile" "$newname"
        fi
    done

    # Adjust ownership and permissions of the daemon log directory and its contents.
    if [ -n "$SUDO_USER" ]; then
        log_info "Changing ownership of $DAEMON_LOG_DIR to user $SUDO_USER"
        sudo chown -R "$SUDO_USER":"$SUDO_USER" "$DAEMON_LOG_DIR"
    fi
    log_info "Setting permissions on $DAEMON_LOG_DIR and its files."
    # Directories: rwxr-xr-x; Files: rw-r--r--
    find "$DAEMON_LOG_DIR" -type d -exec chmod 0755 {} \;
    find "$DAEMON_LOG_DIR" -type f -exec chmod 0644 {} \;
}

# --- Cleanup Routine (for connect) ---
function cleanup() {
    log_info "Cleaning up: Unmounting filesystems..."
    unmount_filesystems
    log_info "Cleanup complete."
}

# --- Command: create ---
function create() {
    # Require root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: The 'create' command must be run as root (use sudo)." >&2
        exit 1
    fi

    check_dependencies
    if [ -d "$CHROOT_DIR" ]; then
        log_error "Chroot jail already exists at $CHROOT_DIR."
        echo "Use 'connect' to enter it, or 'disconnect' if mounts remain."
        exit 1
    fi

    log_info "Creating chroot jail at $CHROOT_DIR using debootstrap..."
    if ! sudo mkdir -p "$CHROOT_DIR"; then
        log_error "Failed to create directory $CHROOT_DIR."
        exit 1
    fi

    if sudo debootstrap stable "$CHROOT_DIR" "$DEBIAN_MIRROR"; then
        log_info "Chroot jail successfully created."
    else
        log_error "debootstrap failed. Check your network and settings."
        exit 1
    fi
}

# --- Command: connect ---
function connect() {
    # Require root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: The 'connect' command must be run as root (use sudo)." >&2
        exit 1
    fi

    check_dependencies
    check_jail

    # Set trap for cleanup when connect ends.
    trap cleanup EXIT SIGINT SIGTERM SIGHUP

    # Mount the required filesystems
    mount_filesystems

    # Allow all connections to the X server
    log_info "Running 'xhost +' to allow X connections..."
    if ! xhost +; then
        log_error "Error running 'xhost +'."
        exit 1
    fi

    # Get the current X authentication keys
    log_info "Retrieving X authentication keys with 'xauth list'..."
    local xauth_keys
    xauth_keys=$(xauth list)
    if [ -z "$xauth_keys" ]; then
        log_error "Warning: 'xauth list' returned no output."
    else
        if command -v xclip &>/dev/null; then
            echo "$xauth_keys" | xclip -selection clipboard
            log_info "X authentication keys have been copied to your clipboard."
        else
            log_info "xclip not found. Here are your X authentication keys:"
            echo "$xauth_keys"
        fi
    fi

    echo ""
    echo "------------------------------"
    echo "Now entering the chroot environment."
    echo "Inside the chroot, add the X authentication key by running:"
    echo "   xauth add <paste-from-clipboard>"
    echo "For example, if your clipboard contains:"
    echo "   $(echo "$xauth_keys" | head -n 1)"
    echo "then run:"
    echo "   xauth add $(echo "$xauth_keys" | head -n 1)"
    echo "------------------------------"
    echo "Press Enter to continue..."
    read -r

    log_info "Entering chroot at $CHROOT_DIR..."
    if [ "$DAEMON" -eq 1 ]; then
        # Create the daemon log directory if it doesn't exist.
        if [ ! -d "$DAEMON_LOG_DIR" ]; then
            mkdir -p "$DAEMON_LOG_DIR" || {
                log_error "Failed to create daemon log directory: $DAEMON_LOG_DIR"
                exit 1
            }
        fi
        log_info "Daemon mode enabled. Monitoring chroot session with strace."
        # Run chroot under strace so that all system calls (and those of forked children)
        # are logged to files with prefix "$DAEMON_LOG_DIR/chroot_daemon.log"
        strace -ff -tt -o "$DAEMON_LOG_DIR/chroot_daemon.log" sudo chroot "$CHROOT_DIR"
        # Post-process the generated logs
        post_process_daemon_logs
    else
        sudo chroot "$CHROOT_DIR"
    fi
    log_info "Chroot session ended."
    # When the chroot session ends, cleanup is automatically triggered by trap.
}

# --- Command: disconnect ---
function disconnect() {
    # Require root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: The 'disconnect' command must be run as root (use sudo)." >&2
        exit 1
    fi

    check_jail

    # Check if any bind mounts exist.
    if ! mount | grep -q "$CHROOT_DIR"; then
        log_info "Chroot environment appears to be clean; no mounts found at $CHROOT_DIR."
        exit 0
    fi

    log_info "Running disconnect: unmounting chroot filesystems..."
    unmount_filesystems

    # Revoke X server permissions.
    if xhost -; then
        log_info "X server access has been revoked."
    else
        log_error "Warning: failed to revoke X server permissions with 'xhost -'."
    fi
}

# --- Command: status ---
function status() {
    echo "Mount status for chroot jail ($CHROOT_DIR):"
    mount | grep "$CHROOT_DIR" || echo "No mounts found for $CHROOT_DIR."
}

# --- Command: install ---
function install_program() {
    # Require root.
    if [ "$EUID" -ne 0 ]; then
        echo "Error: The 'install' command must be run as root (use sudo)." >&2
        exit 1
    fi

    # Resolve the full path of the current script.
    script_path=$(readlink -f "$0")
    log_info "Installing chroot_manager from $script_path to /usr/local/bin/chroot_manager..."
    cp "$script_path" /usr/local/bin/chroot_manager || { log_error "Failed to copy script."; exit 1; }
    chmod 0755 /usr/local/bin/chroot_manager

    # Install the man page if available.
    if [ -e "chroot_manager.1" ]; then
        log_info "Installing man page..."
        mkdir -p /usr/local/share/man/man1
        cp chroot_manager.1 /usr/local/share/man/man1/chroot_manager.1 || { log_error "Failed to copy man page."; }
        gzip -f /usr/local/share/man/man1/chroot_manager.1
    else
        log_debug "No man page (chroot_manager.1) found in the current directory."
    fi

    # Install bash completions if available.
    if [ -e "chroot_manager.bash_completion" ]; then
        log_info "Installing bash completion..."
        cp chroot_manager.bash_completion /etc/bash_completion.d/chroot_manager || { log_error "Failed to install bash completion."; }
    else
        log_debug "No bash completion file found in the current directory."
    fi

    log_info "Installation complete."
}

# --- Command: uninstall ---
function uninstall_program() {
    # Require root.
    if [ "$EUID" -ne 0 ]; then
        echo "Error: The 'uninstall' command must be run as root (use sudo)." >&2
        exit 1
    fi

    log_info "Uninstalling chroot_manager from /usr/local/bin..."
    rm -f /usr/local/bin/chroot_manager

    log_info "Removing man page..."
    rm -f /usr/local/share/man/man1/chroot_manager.1.gz

    log_info "Removing bash completion..."
    rm -f /etc/bash_completion.d/chroot_manager

    log_info "Uninstallation complete."
}

# --- Main CLI Processing ---
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

# Process options.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help_message
            exit 0
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --daemon)
            DAEMON=1
            shift
            ;;
        create|connect|disconnect|status|install|uninstall|help)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option or command: $1"
            usage
            exit 1
            ;;
    esac
done

# Dispatch command.
case "$COMMAND" in
    create)
        create
        ;;
    connect)
        connect
        ;;
    disconnect)
        disconnect
        ;;
    status)
        status
        ;;
    install)
        install_program
        ;;
    uninstall)
        uninstall_program
        ;;
    help)
        help_message
        ;;
    *)
        echo "Invalid command."
        usage
        exit 1
        ;;
esac

