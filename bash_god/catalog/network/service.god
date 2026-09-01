@title Network commands

@description
Curated network knowledge for interfaces, routes, listening ports, DNS, connectivity, HTTP, and
SSH. A plain interactive search lets an operator review, edit, and explicitly run a selected
command through tools on PATH.

@execution PATH


@group interfaces

@command Show Linux network interfaces and addresses
@mode LOCAL
@description
Displays a compact list of Linux interfaces, operational state, and assigned IP addresses.
@run
ip -brief address
@end

@command Show Linux routing table
@mode LOCAL
@description
Displays connected networks, gateways, default route, devices, and route metrics.
@run
ip route show
@end

@command Show the Linux route to one destination
@mode LOCAL
@description
Shows the interface, gateway, source address, and route Linux would use for one destination.
@run
ip route get <destination_ip>
@params
DESTINATION | <destination_ip> | Destination IP whose selected route should be explained
@end

@command Show interfaces with ifconfig
@mode LOCAL
@description
Displays interface addresses and statistics on macOS or hosts where ifconfig is installed.
@run
ifconfig
@notes
Many modern Linux distributions prefer ip address; ifconfig may require the optional net-tools package.
@end

@command Show the macOS default route
@mode LOCAL
@description
Displays the default gateway and interface selected by macOS.
@run
route -n get default
@end


@group ports

@command List listening TCP and UDP ports on Linux
@mode LOCAL
@description
Shows listening sockets, numeric addresses, ports, and owning processes when permissions allow.
@run
ss -tulnp
@end

@command Check which Linux process is listening on one TCP port
@mode LOCAL
@description
Checks listening TCP sockets for a specific port and shows the owning process when permitted.
@run
ss -ltnp | grep ':<port_number>'
@params
PORT | <port_number> | Listening TCP port to find, such as 9200
@notes
Use sudo when process details are hidden by operating-system permissions.
@end

@command Find a listening port with legacy netstat
@mode LOCAL
@description
Uses netstat to find TCP or UDP listeners on hosts where ss is unavailable.
@run
netstat -tulnp | grep ':<port_number>'
@params
PORT | <port_number> | Listening port to find, such as 8083
@notes
netstat may require the optional net-tools package on modern Linux systems.
@end

@command Find the process listening on one TCP port with lsof
@mode LOCAL
@description
Shows the executable, process ID, user, and socket bound to one TCP port.
@run
lsof -nP -iTCP:<port_number> -sTCP:LISTEN
@params
PORT | <port_number> | Listening TCP port to inspect, such as 9200
@end

@command List listening TCP ports with lsof
@mode LOCAL
@description
Lists all TCP listening sockets and their owning processes without resolving names or services.
@run
lsof -nP -iTCP -sTCP:LISTEN
@end


@group dns

@command Resolve a hostname through the system resolver
@mode LOCAL
@description
Resolves a hostname using the operating system's configured name-service sources, including DNS and /etc/hosts.
@run
getent hosts <hostname>
@params
HOST | <hostname> | Hostname to resolve
@notes
getent is common on Linux; use dscacheutil -q host -a name <hostname> on macOS.
@end

@command Show short IPv4 DNS answers
@mode LOCAL
@description
Displays only IPv4 addresses returned for one hostname.
@run
dig +short <hostname> A
@params
HOST | <hostname> | DNS name whose A records should be resolved
@end

@command Inspect a complete DNS response
@mode LOCAL
@description
Displays the DNS question, answer, authority, server, response code, and timing for one name.
@run
dig <hostname>
@params
HOST | <hostname> | DNS name to inspect
@end

@command Resolve a hostname with nslookup
@mode LOCAL
@description
Queries the configured resolver for one hostname on systems where nslookup is available.
@run
nslookup <hostname>
@params
HOST | <hostname> | Hostname to resolve
@end

@command Inspect static host mappings
@mode LOCAL
@description
Displays local hostname-to-address mappings that may override or supplement DNS resolution.
@run
cat /etc/hosts
@notes
/etc/hosts can contain private infrastructure names; review the output before sharing it.
@end

@command Show Linux resolver configuration
@mode LOCAL
@description
Displays configured DNS servers, search domains, per-link settings, and DNSSEC state on systemd-resolved hosts.
@run
resolvectl status
@end

@command Show macOS resolver configuration
@mode LOCAL
@description
Displays the effective DNS resolvers, search domains, and interface-specific resolver order on macOS.
@run
scutil --dns
@end


@group connectivity

@command Send four ICMP probes to a host
@mode LOCAL
@description
Checks basic reachability and reports packet loss and round-trip latency without running indefinitely.
@run
ping -c 4 <host>
@params
-c | 4 | Stop after four probes
HOST | <host> | Hostname or IP address to test
@end

@command Trace the network path to a host
@mode LOCAL
@description
Shows the sequence of routers reached on the path toward one host.
@run
traceroute -m 10 -w 2 <host>
@params
-m | 10 | Stop after ten hops instead of waiting for the platform default
-w | 2 | Wait at most two seconds for each probe response
HOST | <host> | Hostname or IP address whose route should be traced
@end

@command Test whether a remote TCP port accepts connections
@mode LOCAL
@description
Attempts a verbose TCP connection with a short timeout without sending an application payload.
@run
nc -vz -w 5 <host> <port_number>
@params
-w | 5 | Connection timeout in seconds
HOST | <host> | Remote hostname or IP address
PORT | <port_number> | Remote TCP port to test
@end


@group http

@command Show HTTP response headers
@mode LOCAL
@description
Requests only response headers so status, redirects, server metadata, and cache behavior can be inspected.
@run
curl -sS -I <url>
@params
-I | flag | Send a HEAD request and display response headers
URL | <url> | HTTP or HTTPS endpoint to inspect
@end

@command Show verbose HTTP connection diagnostics
@mode LOCAL
@description
Shows DNS resolution, connection setup, TLS negotiation, request headers, and response headers while discarding the body.
@run
curl -v <url> -o /dev/null
@params
-v | flag | Print connection and protocol diagnostics
URL | <url> | HTTP or HTTPS endpoint to inspect
@notes
Verbose output can expose authorization and cookie headers; review it before sharing.
@end

@command Save a complete curl trace
@mode LOCAL
@risk WRITE
@description
Writes a detailed ASCII trace of an HTTP exchange to a local file while discarding the response body.
@run
curl --trace-ascii <trace_file> <url> -o /dev/null
@params
--trace-ascii | <trace_file> | Local trace file that will be created or overwritten
URL | <url> | HTTP or HTTPS endpoint to inspect
@notes
Trace files can contain credentials, cookies, request bodies, and private response data; protect and review them before sharing.
@end

@command Show HTTP status and total request time
@mode LOCAL
@description
Prints only the final HTTP status code and total elapsed time while discarding the response body.
@run
curl -sS -o /dev/null -w 'status=%{http_code} total=%{time_total}s\n' <url>
@params
-w | status and total | Output fields to print after the request
URL | <url> | HTTP or HTTPS endpoint to measure
@end

@command Inspect a server TLS handshake and certificate chain
@mode LOCAL
@description
Connects with SNI and displays the negotiated TLS session and certificates presented by the server.
@run
openssl s_client -connect <host>:<port_number> -servername <host> </dev/null
@params
-connect | <host>:<port_number> | TLS server and port, commonly 443
-servername | <host> | Server Name Indication value for virtual hosting
@end


@group ssh

@command Connect to a host through SSH
@mode LOCAL
@risk WARN
@description
Starts a normal SSH session using the selected user and resolvable hostname.
@run
ssh <user>@<host>
@params
USER | <user> | Remote login user
HOST | <host> | Remote hostname or IP address
@notes
Agent forwarding is not enabled; do not add -A unless the environment explicitly requires and approves it.
@end

@command Connect to SSH on a non-default port
@mode LOCAL
@risk WARN
@description
Starts an SSH session when the server is listening somewhere other than TCP port 22.
@run
ssh -p <port_number> <user>@<host>
@params
-p | <port_number> | Remote SSH port
USER | <user> | Remote login user
HOST | <host> | Remote hostname or IP address
@notes
Starts an interactive remote shell; verify the host, user, and port before connecting.
@end

@command Diagnose an SSH connection verbosely
@mode LOCAL
@risk WARN
@description
Shows configuration selection, key negotiation, authentication attempts, and connection progress.
@run
ssh -vvv <user>@<host>
@params
-vvv | flag | Enable the highest normal client debug verbosity
USER | <user> | Remote login user
HOST | <host> | Remote hostname or IP address
@notes
Verbose logs reveal hostnames, usernames, key fingerprints, and configuration paths; review them before sharing.
@end

@command Connect through an SSH jump host
@mode LOCAL
@risk WARN
@description
Uses one approved bastion or jump host to reach a target host without enabling agent forwarding.
@run
ssh -J <jump_user>@<jump_host> <target_user>@<target_host>
@params
-J | <jump_user>@<jump_host> | SSH jump host and login user
TARGET | <target_user>@<target_host> | Final SSH destination
@notes
Starts an interactive remote shell through the selected jump host; verify both destinations before connecting.
@end

@command Connect with one explicit SSH identity
@mode LOCAL
@risk WARN
@description
Uses one selected private key and prevents the client from offering unrelated agent identities.
@run
ssh -o IdentitiesOnly=yes -i <identity_file> <user>@<host>
@params
-i | <identity_file> | Path to the private key authorized for this host
IdentitiesOnly | yes | Offer only explicitly configured identities
@notes
Keep private keys outside the catalog and restrict their filesystem permissions.
@end


@group native

@command Show ip command help
@mode LOCAL
@description
Displays the top-level objects and options supported by the installed Linux ip command.
@run
ip help
@end

@command Show curl native help
@mode LOCAL
@description
Displays curl's installed command-line help and points to option-specific help categories when supported.
@run
curl --help
@end

@command Show effective SSH client configuration
@mode LOCAL
@description
Prints the final SSH configuration produced after applying user, host, wildcard, and system configuration blocks.
@run
ssh -G <user>@<host>
@params
USER | <user> | Remote login user used for configuration matching
HOST | <host> | Host or alias used for configuration matching
@end
