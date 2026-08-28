@title General host commands

@description
Curated host and operating-system knowledge for identifying a machine, inspecting its resources and
processes, and working with common files. Commands are displayed as inert text and are never
executed by BASH_GOD.


@group host

@command Show the current hostname
@mode LOCAL
@description
Prints the hostname of the machine where the shell is currently running.
@run
hostname
@end

@command Show uptime and load averages
@mode LOCAL
@description
Shows how long the host has been running, logged-in user count, and recent load averages.
@run
uptime
@end

@command Show the Linux distribution
@mode LOCAL
@description
Displays the installed Linux distribution name, version, and related release metadata.
@run
cat /etc/os-release
@notes
This file is normally present on Linux; use sw_vers on macOS.
@end

@command Show the macOS version
@mode LOCAL
@description
Displays the installed macOS product name, version, and build.
@run
sw_vers
@end

@command Show kernel and machine architecture
@mode LOCAL
@description
Displays the kernel release, hostname, and CPU architecture reported by the operating system.
@run
uname -a
@end

@command Show the current user and groups
@mode LOCAL
@description
Displays the current user ID, primary group, and supplementary group memberships.
@run
id
@end

@command Show the current shell environment
@mode LOCAL
@description
Lists exported environment variables in a stable alphabetical order.
@run
env | sort
@notes
Environment variables can contain credentials and tokens; review the output before copying or sharing it.
@end

@command Switch to another user and keep the current environment
@mode LOCAL
@description
Starts a shell as another local user without resetting the exported environment, so variables set in the current session stay visible.
@run
sudo -u <target_user> -E bash
@params
-u | <target_user> | Local account that will own the new shell
-E | flag | Preserve the caller's exported environment instead of resetting it
bash | non-login shell | Avoid a login shell, which would re-read the target user's profile and discard the environment
@notes
sudoers enforces env_reset by default, so -E keeps only variables allowed by an env_keep rule; adding one such as Defaults env_keep += "AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN" in a file under /etc/sudoers.d is what lets those variables survive.
@end

@command Switch to another user with a clean login shell
@mode LOCAL
@description
Starts a full login shell as another local user, reading that user's profile and discarding variables exported before the switch.
@run
sudo su - <target_user>
@params
su - | login shell | Reset the environment and working directory to the target user's login defaults
<target_user> | ec2-user | Local account whose login shell will start
@notes
The leading dash is why exported variables disappear after the switch; use the environment-preserving form when the current session's variables must survive.
@end


@group resources

@command Show Linux memory totals
@mode LOCAL
@description
Shows total, used, available, shared, buffer, cache, and swap memory in human-readable units.
@run
free -h
@end

@command Show the first Linux kernel memory counters
@mode LOCAL
@description
Displays the leading totals from /proc/meminfo for a quick view of RAM and available memory.
@run
head -n 5 /proc/meminfo
@params
-n | 5 | Number of leading memory counters to display
@end

@command Show Linux CPU architecture and topology
@mode LOCAL
@description
Displays CPU architecture, logical CPUs, cores, sockets, NUMA layout, and virtualization details.
@run
lscpu
@end

@command Show Linux CPU cores and model names
@mode LOCAL
@description
Shows a short sample of processor IDs and model names from the kernel CPU inventory.
@run
grep -E '^(processor|model name)' /proc/cpuinfo | head -n 10
@params
-E | processor or model name | Match the two useful CPU inventory fields
-n | 10 | Limit the output to a short sample
@end

@command Show macOS CPU model and core counts
@mode LOCAL
@description
Displays the Mac CPU model plus physical and logical core counts.
@run
sysctl -n machdep.cpu.brand_string hw.physicalcpu hw.logicalcpu
@end

@command Show NVIDIA GPU status
@mode LOCAL
@description
Displays detected NVIDIA GPUs, driver version, utilization, temperature, and memory usage.
@run
nvidia-smi
@notes
This command is available only when NVIDIA drivers and their management utility are installed.
@end

@command Show macOS display and GPU information
@mode LOCAL
@description
Displays graphics hardware, displays, VRAM, and Metal support reported by macOS.
@run
system_profiler SPDisplaysDataType
@end

@command Sample macOS GPU power telemetry
@mode LOCAL
@description
Collects five one-second GPU power samples from macOS powermetrics.
@run
sudo powermetrics --samplers gpu_power -i 1000 -n 5
@params
--samplers | gpu_power | Collect GPU power telemetry
-i | 1000 | Sampling interval in milliseconds
-n | 5 | Stop after five samples
@notes
powermetrics requires administrator authorization but only reads telemetry.
@end

@command Show mounted filesystem capacity
@mode LOCAL
@description
Shows total, used, available, and mounted capacity for filesystems in human-readable units.
@run
df -h
@end

@command Show Linux block devices and filesystems
@mode LOCAL
@description
Displays disks, partitions, filesystem types, labels, UUIDs, and mount points.
@run
lsblk -f
@end

@command Sample Linux disk I/O performance
@mode LOCAL
@description
Collects three extended disk-utilization samples at one-second intervals.
@run
iostat -xz 1 3
@params
-x | flag | Show extended device statistics
-z | flag | Omit devices with no activity
1 | seconds | Interval between samples
3 | samples | Stop after three reports
@notes
iostat is commonly provided by sysstat; BASH_GOD does not install it when absent.
@end

@command Show the size of one directory
@mode LOCAL
@description
Calculates the total disk space used below one directory.
@run
du -sh <directory>
@params
DIRECTORY | <directory> | Directory whose total size should be calculated
@end


@group processes

@command Open the standard interactive process viewer
@mode LOCAL
@description
Shows live CPU, memory, load, and process activity using the standard top interface.
@run
top
@notes
Press q to leave top.
@end

@command Open the enhanced interactive process viewer
@mode LOCAL
@description
Shows live processes in the more navigable htop interface when it is installed.
@run
htop
@notes
htop is optional; BASH_GOD does not install it when absent.
@end

@command Show the busiest Linux processes by CPU
@mode LOCAL
@description
Lists the ten processes currently using the most CPU with useful ownership and runtime fields.
@run
ps -eo pid,user,%cpu,%mem,etime,command --sort=-%cpu | head -n 11
@end

@command Find a process by name or command line
@mode LOCAL
@description
Finds running processes whose full command line matches a case-insensitive pattern.
@run
pgrep -ifl '<process_pattern>'
@params
PATTERN | <process_pattern> | Process name or command-line text to find
@end

@command Show a systemd service status
@mode LOCAL
@description
Shows whether a Linux service is running plus its process details and recent log lines.
@run
systemctl status <service_name> --no-pager
@params
SERVICE | <service_name> | systemd unit to inspect, such as mongod or elasticsearch
@end

@command Show recent logs for a systemd service
@mode LOCAL
@description
Displays the latest journal entries for one Linux service without following indefinitely.
@run
journalctl -u <service_name> -n 100 --no-pager
@params
-u | <service_name> | systemd unit whose journal should be read
-n | 100 | Number of recent log lines
@end


@group files

@command List files with useful details
@mode LOCAL
@description
Lists hidden and visible files with permissions, ownership, size, and modification time.
@run
ls -lah <directory>
@params
DIRECTORY | <directory> | Directory to list
@end

@command Find files by name
@mode LOCAL
@description
Recursively finds files whose names match one shell-style pattern below a selected directory.
@run
find <directory> -type f -name '<name_pattern>'
@params
DIRECTORY | <directory> | Root directory for the search
PATTERN | <name_pattern> | Filename pattern such as *.log
@end

@command Search file contents recursively
@mode LOCAL
@description
Finds case-insensitive text matches with filenames and line numbers below a selected directory.
@run
grep -Rni -- '<search_text>' <directory>
@params
TEXT | <search_text> | Literal or basic regular-expression text to find
DIRECTORY | <directory> | Root directory for the search
@end

@command Follow the latest lines of a log file
@mode LOCAL
@description
Shows the latest one hundred lines and continues printing new lines as they are appended.
@run
tail -n 100 -f <log_file>
@params
-n | 100 | Number of existing lines to display first
FILE | <log_file> | Log file to follow
@notes
Press Ctrl-C to stop following the file.
@end

@command Create a compressed tar archive
@mode LOCAL
@risk WRITE
@description
Creates a gzip-compressed archive containing one directory and its contents.
@run
tar -czvf <archive_name>.tgz <directory>
@params
ARCHIVE | <archive_name>.tgz | New archive file that will be created or overwritten
DIRECTORY | <directory> | Directory to include in the archive
@end

@command List a compressed tar archive without extracting it
@mode LOCAL
@description
Displays the files stored in a gzip-compressed tar archive without changing the filesystem.
@run
tar -tzf <archive_name>.tgz
@params
ARCHIVE | <archive_name>.tgz | Archive whose contents should be inspected
@end


@group native

@command Find how the shell resolves a command
@mode LOCAL
@description
Shows whether a name resolves to an alias, function, builtin, or executable path.
@run
type -a <command_name>
@params
COMMAND | <command_name> | Command name to resolve
@end

@command Open a command manual
@mode LOCAL
@description
Opens the installed manual page for a native command.
@run
man <command_name>
@params
COMMAND | <command_name> | Native command whose manual should be opened
@end

@command Show Bash builtin help
@mode LOCAL
@description
Displays Bash's built-in documentation for a shell builtin such as cd, read, or printf.
@run
help <builtin_name>
@params
BUILTIN | <builtin_name> | Bash builtin to explain
@end
