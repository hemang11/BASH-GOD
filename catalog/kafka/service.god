@title Kafka commands

@description
A personal Kafka operator knowledge base covering access, setup, brokers, configuration, topics,
consumer groups, offsets, consuming, producing, health, ZooKeeper, KRaft, replication, security,
and native tool help. Commands are shown for review and, once BASH_GOD resolves this machine's
install and you confirm, can be run directly. Static examples keep the familiar native Kafka
spelling; the reviewed runtime model resolves only the explicitly required sibling tool.

@discover
probe | kafka-topics.sh | Core topic-management tool; presence marks a resolved Kafka install
root | /opt/kafka/bin | Common Kafka install layout
scan | /opt | Bounded scan root when the common layout is absent
version | kafka-topics.sh --version 2>/dev/null; [ $? -ne 0 ] && { f=$(echo ../libs/kafka_*.jar); v=${f##*-}; echo ${v%.jar}; } | Kafka >=2.4 prints the version directly; older builds have no --version flag, so this falls back to the version embedded in the libs/kafka_<scala>-<version>.jar filename

@connection ENDPOINT 9092

@synced 3.9

@environment 1
os | local | any
context | execution | local
shell | local | none

@group access

@command SSH to a Kafka host
@mode LOCAL
@since 0.0
@requires
tool | local:ssh | present
@description
Connects to an SSH host from which the Kafka environment is reachable.
@run
ssh <kafka_host>
@params
HOST | <kafka_host> | SSH alias or resolvable hostname for the Kafka environment
@notes
Use your environment's approved access path. BASH_GOD does not enable agent forwarding.
@end

@group setup

@command Find the Kafka command directory
@mode LOCAL
@since 0.0
@requires
shell | local | posix
tool | local:find | present
@description
Searches /opt for the Kafka console-consumer executable so its parent directory can be used as the bin directory.
@run
find /opt -type f \( -name 'kafka-console-consumer.sh' -o -name 'kafka-console-consumer' \) 2>/dev/null
@notes
If the result is /opt/kafka/bin/kafka-console-consumer.sh, use /opt/kafka/bin as the command directory.
@end

@command Show the installed Kafka version
@mode MODERN
@since 0.0
@requires
tool | service:kafka-topics.sh | present
@description
Asks the installed topic tool to print its Kafka version.
@run
./kafka-topics.sh --version
@end

@command List installed Kafka command-line tools
@mode LOCAL
@since 0.0
@requires
shell | local | posix
tool | local:find | present
tool | local:sort | present
@description
Lists Kafka executables available in one Kafka bin directory.
@run
find <kafka_bin_directory> -maxdepth 1 -type f -name 'kafka-*' -print | sort
@params
DIRECTORY | <kafka_bin_directory> | Kafka bin directory to inspect
@end


@group broker

@command Check the Kafka systemd service
@mode LOCAL
@since 0.0
@requires
os | local | linux
tool | local:systemctl | present
@description
Shows whether the local Kafka service is running and displays recent service status.
@run
systemctl status kafka
@params
SERVICE | kafka | Local systemd unit name; it may be kafka-server on some hosts
@end

@command Find the running Kafka process
@mode LOCAL
@since 0.0
@requires
tool | local:pgrep | present
@description
Shows Kafka JVM processes and their launch arguments.
@run
pgrep -af 'kafka.Kafka|Kafka'
@end

@command Find the local Kafka broker listener
@mode LOCAL
@since 0.0
@requires
os | local | linux
tool | local:ss | present
@description
Shows the local address accepting Kafka broker TCP connections on the usual port.
@run
ss -ltn 'sport = :9092'
@params
PORT | 9092 | Usual Kafka broker TCP port
@end

@command Show recent Kafka service logs
@mode LOCAL
@since 0.0
@requires
os | local | linux
tool | local:journalctl | present
@description
Displays the latest systemd journal entries for the Kafka service.
@run
journalctl -u kafka -n 200 --no-pager
@params
-u | kafka | Kafka systemd unit name
-n | 200 | Number of recent journal lines
@end

@command Show broker configuration
@mode LOCAL
@since 0.0
@requires
tool | local:cat | present
@description
Displays one selected broker server.properties file.
@run
cat <kafka_config_file>
@params
FILE | <kafka_config_file> | Broker server.properties file to inspect
@end

@command Show broker log-directory disk usage
@mode LOCAL
@since 0.0
@requires
tool | local:du | present
@description
Displays space used by the example broker data directory.
@run
du -sh /tmp/kafka-logs
@params
DIRECTORY | /tmp/kafka-logs | Example value; confirm log.dirs before using it
@end


@group config

@command Show important broker settings
@mode LOCAL
@since 0.0
@requires
tool | local:grep | present
@description
Extracts identity, listener, storage, ZooKeeper, and KRaft settings from one server.properties file.
@run
grep -E '^(broker.id|node.id|listeners|advertised.listeners|log.dirs|zookeeper.connect|process.roles|controller.quorum)' <kafka_config_file>
@params
FILE | <kafka_config_file> | Broker server.properties file to inspect
@end

@command Show Kafka client properties
@mode LOCAL
@since 0.0
@requires
tool | local:cat | present
@description
Displays one client properties file commonly passed through --command-config.
@run
cat <kafka_client_properties_file>
@params
FILE | <kafka_client_properties_file> | Client properties file to inspect
@notes
Client properties can contain authentication material; review the file before sharing its output.
@end

@command Describe one topic's dynamic configuration
@mode MODERN
@since 2.6
@requires
tool | service:kafka-configs.sh | present
@description
Shows topic-level configuration overrides such as retention and cleanup policy.
@run
./kafka-configs.sh --bootstrap-server localhost:9092 --entity-type topics --entity-name <topic_name> --describe
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--entity-type | topics | Configuration entity category
--entity-name | <topic_name> | Topic whose overrides should be displayed
--describe | flag | Read the current configuration
@end

@command Describe one broker's dynamic configuration
@mode MODERN
@since 1.1
@requires
tool | service:kafka-configs.sh | present
@description
Shows dynamic configuration overrides for a broker ID.
@run
./kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers --entity-name <broker_id> --describe
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--entity-type | brokers | Configuration entity category
--entity-name | <broker_id> | Broker ID to inspect
--describe | flag | Read the current configuration
@end

@command Describe cluster-wide broker defaults
@mode MODERN
@since 1.1
@requires
tool | service:kafka-configs.sh | present
@description
Shows dynamic broker defaults that apply across the cluster.
@run
./kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers --entity-default --describe
@params
--entity-default | flag | Select the cluster-wide broker default entity
@end

@command Describe user quota configuration
@mode MODERN
@since 2.6
@requires
tool | service:kafka-configs.sh | present
@description
Lists dynamic quota and authentication-related configuration for Kafka users.
@run
./kafka-configs.sh --bootstrap-server localhost:9092 --entity-type users --describe
@params
--entity-type | users | Inspect user entities
--describe | flag | Read current values
@end


@group topics

@command List topics through a broker
@mode MODERN
@since 2.2
@intent list-topics
@requires
tool | service:kafka-topics.sh | present
@description
Lists topics available through the selected Kafka cluster.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --list
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--list | flag | List topic names
@end

@command Describe a topic through a broker
@mode MODERN
@since 2.2
@intent describe-topic
@requires
tool | service:kafka-topics.sh | present
@description
Shows partitions, leaders, replicas, in-sync replicas, and topic configuration.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic <topic_name>
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--describe | flag | Display topic metadata
--topic | <topic_name> | Topic to inspect
@end

@command Create a topic
@mode MODERN
@since 2.2
@risk WRITE
@requires
tool | service:kafka-topics.sh | present
@description
Creates a topic with an explicit partition count and replication factor.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --create --topic <topic_name> --partitions 3 --replication-factor 3
@params
--topic | <topic_name> | New topic name
--partitions | 3 | Number of partitions to create
--replication-factor | 3 | Number of replicas per partition
@end

@command Add partitions to an existing topic
@mode MODERN
@since 2.2
@risk WRITE
@requires
tool | service:kafka-topics.sh | present
@description
Increases a topic's total partition count; Kafka cannot reduce it later.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --alter --topic <topic_name> --partitions <new_total>
@params
--topic | <topic_name> | Topic to change
--partitions | <new_total> | New total partition count, not the number to add
@end

@command Delete a topic
@mode MODERN
@since 2.2
@risk DELETE
@requires
tool | service:kafka-topics.sh | present
@description
Requests deletion of a topic and its retained records.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic <topic_name>
@params
--topic | <topic_name> | Topic and retained data to delete
@end

@command Describe every topic
@mode MODERN
@since 2.2
@requires
tool | service:kafka-topics.sh | present
@description
Displays partition and replica metadata for all visible topics.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --describe
@end


@group groups

@command List consumer groups
@mode MODERN
@since 0.10.1
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Lists consumer groups known to the selected Kafka cluster.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --list
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--command-config | <kafka_client_properties_file> | Optional AdminClient security properties
--list | flag | List consumer-group names
@end

@command Show active members of a consumer group
@mode MODERN
@since 1.0
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Shows active consumer IDs, hosts, client IDs, and member counts.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --describe --group <consumer_group> --members
@params
--group | <consumer_group> | Consumer group to inspect
--members | flag | Display active group members
@end

@command Show group partition assignments
@mode MODERN
@since 1.0
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Shows every member and the topic partitions assigned to it.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --describe --group <consumer_group> --members --verbose
@params
--group | <consumer_group> | Consumer group to inspect
--members | flag | Display active members
--verbose | flag | Include partition assignments
@end

@command Show consumer-group state
@mode MODERN
@since 1.0
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Shows the coordinator, assignment strategy, state, and number of members.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --describe --group <consumer_group> --state
@params
--group | <consumer_group> | Consumer group to inspect
--state | flag | Display group-level state
@end

@command Delete an inactive consumer group
@mode MODERN
@since 1.1
@risk DELETE
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Deletes consumer-group metadata when no active members remain.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --delete --group <consumer_group>
@params
--delete | flag | Delete consumer-group metadata
--group | <consumer_group> | Inactive group to delete
@end


@group offset

@command Show consumer-group offsets and lag
@mode MODERN
@since 0.10.1
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Shows committed offsets, log-end offsets, and lag for each assigned partition.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config <kafka_client_properties_file> --group <consumer_group> --describe
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--command-config | <kafka_client_properties_file> | Optional AdminClient security properties
--group | <consumer_group> | Consumer group whose offsets should be inspected
--describe | flag | Display offsets and lag
@end

@command Show earliest offsets for a topic
@mode MODERN
@since 3.0
@requires
tool | service:kafka-get-offsets.sh | present
@description
Shows the oldest available offset for every selected topic partition.
@run
./kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic <topic_name> --time -2
@params
--topic | <topic_name> | Topic whose partition offsets should be inspected
--time | -2 | Kafka sentinel for earliest available offsets
@end

@command Show latest offsets for a topic
@mode MODERN
@since 3.0
@requires
tool | service:kafka-get-offsets.sh | present
@description
Shows the current log-end offset for every selected topic partition.
@run
./kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic <topic_name> --time -1
@params
--topic | <topic_name> | Topic whose partition offsets should be inspected
--time | -1 | Kafka sentinel for latest offsets
@end

@command Preview resetting a group to the earliest offsets
@mode MODERN
@since 1.0
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Calculates the offset changes without applying them because --execute is absent.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --topic <topic_name> --reset-offsets --to-earliest
@params
--group | <consumer_group> | Inactive consumer group to calculate for
--topic | <topic_name> | Topic included in the reset preview
--reset-offsets | flag | Enter offset-reset mode
--to-earliest | flag | Calculate earliest available offsets
@end

@command Preview resetting a group to one explicit offset
@mode MODERN
@since 1.0
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Calculates a reset to one requested offset without applying it.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --topic <topic_name>:<partition> --reset-offsets --to-offset <offset>
@params
--topic | <topic_name>:<partition> | Topic partition included in the preview
--to-offset | <offset> | Proposed committed offset
@end

@command Execute an explicit consumer-group offset reset
@mode MODERN
@since 1.0
@risk WARN
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Changes the committed offset for an inactive consumer group.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --topic <topic_name>:<partition> --reset-offsets --to-offset <offset> --execute
@params
--group | <consumer_group> | Inactive consumer group to modify
--topic | <topic_name>:<partition> | Topic partition to modify
--to-offset | <offset> | New committed offset
--execute | flag | Apply the calculated offset reset
@end


@group consume

@command Read from an exact partition offset
@mode MODERN
@since 0.10
@requires
tool | service:kafka-console-consumer.sh | present
@description
Starts a console consumer at one explicit topic partition and offset.
@run
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic <topic_name> --offset <offset> --partition <partition> --max-messages 5 --timeout-ms 10000
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--topic | <topic_name> | Topic containing the records
--offset | <offset> | First offset to read
--partition | <partition> | Partition containing that offset
--max-messages | 5 | Exit after reading five records
--timeout-ms | 10000 | Stop waiting after ten seconds
@end

@command Read a topic from the beginning
@mode MODERN
@since 0.10
@requires
tool | service:kafka-console-consumer.sh | present
@description
Reads existing topic records beginning with the earliest retained offset.
@run
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic <topic_name> --from-beginning --max-messages 5 --timeout-ms 10000
@params
--topic | <topic_name> | Topic to consume
--from-beginning | flag | Begin at the earliest retained offset
--max-messages | 5 | Exit after reading five records
--timeout-ms | 10000 | Stop waiting after ten seconds
@end

@command Read a bounded sample from the beginning
@mode MODERN
@since 0.10
@requires
tool | service:kafka-console-consumer.sh | present
@description
Reads a small existing sample and exits on count or timeout.
@run
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic <topic_name> --from-beginning --max-messages 5 --timeout-ms 10000
@params
--max-messages | 5 | Exit after five records
--timeout-ms | 10000 | Stop waiting after ten seconds
@end

@command Print record keys, headers, and timestamps
@mode MODERN
@since 0.11
@requires
tool | service:kafka-console-consumer.sh | present
@description
Consumes records while exposing metadata useful for debugging serialization and routing.
@run
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic <topic_name> --max-messages 5 --property print.key=true --property print.headers=true --property print.timestamp=true
@params
--property | print.key=true | Include record keys
--property | print.headers=true | Include record headers
--property | print.timestamp=true | Include record timestamps
@end

@command Consume with a client-properties file
@mode MODERN
@since 0.10
@requires
tool | service:kafka-console-consumer.sh | present
@description
Uses a consumer properties file for clusters requiring authentication or TLS settings.
@run
./kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic <topic_name> --consumer.config <kafka_client_properties_file> --max-messages 5
@params
--consumer.config | <kafka_client_properties_file> | Consumer security and client properties
--max-messages | 5 | Exit after five records
@end


@group produce

@command Publish one message
@mode MODERN
@risk WRITE
@since 2.6
@intent publish-message
@requires
shell | local | posix
tool | service:kafka-console-producer.sh | present
@description
Publishes one visible message to a topic through the modern console producer.
@run
echo '<message>' | ./kafka-console-producer.sh --bootstrap-server localhost:9092 --topic <topic_name>
@params
INPUT | <message> | Message value sent to Kafka
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--topic | <topic_name> | Topic that will receive the record
@notes
Create the topic first unless broker auto-creation is enabled. Remove `echo '<message>' |` to enter multiple messages interactively; press Ctrl-D to exit.
@end

@command Publish one message with legacy broker-list syntax
@mode LEGACY-ZK
@since 0.8
@risk WRITE
@until 2.8
@intent publish-message
@requires
shell | local | posix
tool | service:kafka-console-producer.sh | present
@description
Publishes one visible message using the broker option found in older Kafka installations.
@run
echo '<message>' | ./kafka-console-producer.sh --broker-list localhost:9092 --topic <topic_name>
@params
INPUT | <message> | Message value sent to Kafka
--broker-list | localhost:9092 | Legacy producer broker option
--topic | <topic_name> | Topic that will receive the record
@notes
Remove `echo '<message>' |` to enter multiple messages interactively; press Ctrl-D to exit.
@end

@command Publish a keyed message
@mode MODERN
@since 2.6
@risk WRITE
@requires
shell | local | posix
tool | service:kafka-console-producer.sh | present
@description
Publishes one visible record after splitting its key and value at the colon.
@run
echo '<key>:<value>' | ./kafka-console-producer.sh --bootstrap-server localhost:9092 --topic <topic_name> --property parse.key=true --property key.separator=:
@params
INPUT | <key>:<value> | Record key and value separated by a colon
--property | parse.key=true | Parse a key from each input line
--property | key.separator=: | Character separating key from value
@notes
Remove `echo '<key>:<value>' |` to enter multiple keyed messages interactively; press Ctrl-D to exit.
@end

@command Publish records from a file
@mode MODERN
@since 2.6
@risk WRITE
@requires
shell | local | posix
tool | service:kafka-console-producer.sh | present
@description
Publishes each input-file line as one Kafka record.
@run
./kafka-console-producer.sh --bootstrap-server localhost:9092 --topic <topic_name> < messages.txt
@params
--topic | <topic_name> | Topic that will receive the records
FILE | messages.txt | Text file with one record per line
@end


@group health

@command Check broker API compatibility
@mode MODERN
@since 0.10
@requires
tool | service:kafka-broker-api-versions.sh | present
@description
Queries reachable brokers and displays the Kafka API versions they support.
@run
./kafka-broker-api-versions.sh --bootstrap-server localhost:9092
@end

@command Find under-replicated partitions
@mode MODERN
@since 2.2
@requires
tool | service:kafka-topics.sh | present
@description
Lists partitions whose in-sync replica count is below the configured replica set.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions
@params
--under-replicated-partitions | flag | Show partitions missing in-sync replicas
@end

@command Find partitions without an available leader
@mode MODERN
@since 2.2
@requires
tool | service:kafka-topics.sh | present
@description
Lists partitions that currently have no leader and therefore cannot serve traffic.
@run
./kafka-topics.sh --bootstrap-server localhost:9092 --describe --unavailable-partitions
@params
--unavailable-partitions | flag | Show partitions without a leader
@end

@command Describe broker log-directory health
@mode MODERN
@since 1.0
@requires
tool | service:kafka-log-dirs.sh | present
@description
Shows replica sizes and errors for broker log directories.
@run
./kafka-log-dirs.sh --bootstrap-server localhost:9092 --describe
@params
--describe | flag | Read broker log-directory information
@end


@group zookeeper

@command Show ZooKeeper configuration
@mode LEGACY-ZK
@since 0.0
@until 3.9
@requires
tool | local:cat | present
@description
Displays one ZooKeeper properties file for an older Kafka installation.
@run
cat <zookeeper_config_file>
@params
FILE | <zookeeper_config_file> | ZooKeeper properties file to inspect
@end

@command Discover the ZooKeeper data directory
@mode LEGACY-ZK
@since 0.0
@until 3.9
@requires
tool | local:grep | present
@description
Reads dataDir from one ZooKeeper properties file instead of assuming /tmp/zookeeper.
@run
grep '^[[:space:]]*dataDir=' <zookeeper_config_file>
@params
FILE | <zookeeper_config_file> | ZooKeeper properties file to inspect
@notes
/tmp/zookeeper is a common development value, not a universal location.
@end

@command List topics through ZooKeeper
@mode LEGACY-ZK
@since 0.8
@until 2.8
@intent list-topics
@requires
tool | service:kafka-topics.sh | present
@description
Lists topics using the legacy ZooKeeper connection syntax.
@run
./kafka-topics.sh --zookeeper localhost:2181 --list
@params
--zookeeper | localhost:2181 | Legacy ZooKeeper endpoint
--list | flag | List topic names
@end

@command Describe a topic through ZooKeeper
@mode LEGACY-ZK
@since 0.8
@until 2.8
@intent describe-topic
@requires
tool | service:kafka-topics.sh | present
@description
Shows topic metadata using the legacy ZooKeeper connection syntax.
@run
./kafka-topics.sh --zookeeper localhost:2181 --describe --topic <topic_name>
@params
--zookeeper | localhost:2181 | Legacy ZooKeeper endpoint
--topic | <topic_name> | Topic to inspect
@end

@command List broker IDs registered in ZooKeeper
@mode LEGACY-ZK
@since 0.8
@until 3.9
@requires
tool | service:zookeeper-shell.sh | present
@description
Reads the ZooKeeper broker-registration path used by legacy Kafka clusters.
@run
./zookeeper-shell.sh localhost:2181 ls /brokers/ids
@params
ENDPOINT | localhost:2181 | ZooKeeper host and client port
PATH | /brokers/ids | ZooKeeper path containing registered broker IDs
@end


@group kraft

@command Describe KRaft metadata-quorum status
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-metadata-quorum.sh | present
@description
Shows the cluster ID, active controller, voters, observers, and follower lag summary.
@run
./kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status
@params
--bootstrap-server | localhost:9092 | Broker used to reach the KRaft cluster
describe --status | operation | Display quorum status
@end

@command Describe KRaft metadata replication
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-metadata-quorum.sh | present
@description
Shows per-controller and broker metadata offsets, lag, and catch-up timestamps.
@run
./kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --replication
@params
describe --replication | operation | Display detailed metadata replication state
@end

@command Describe finalized Kafka features
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-features.sh | present
@description
Shows supported and finalized feature levels such as metadata.version and kraft.version.
@run
./kafka-features.sh --bootstrap-server localhost:9092 describe
@end

@command Inspect a KRaft metadata snapshot
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-metadata-shell.sh | present
@description
Opens the metadata shell against one local KRaft snapshot file.
@run
./kafka-metadata-shell.sh --snapshot <metadata_snapshot_file>
@params
--snapshot | <metadata_snapshot_file> | Valid KRaft metadata checkpoint or snapshot
@end


@group replication

@command Generate a partition-reassignment proposal
@mode MODERN
@since 2.6
@requires
tool | service:kafka-reassign-partitions.sh | present
@description
Calculates current and proposed replica placement without executing it.
@run
./kafka-reassign-partitions.sh --bootstrap-server localhost:9092 --topics-to-move-json-file topics.json --broker-list '1,2,3' --generate
@params
--topics-to-move-json-file | topics.json | JSON identifying topics to move
--broker-list | 1,2,3 | Candidate destination broker IDs
--generate | flag | Calculate a proposal without applying it
@end

@command Verify a partition reassignment
@mode MODERN
@since 2.6
@requires
tool | service:kafka-reassign-partitions.sh | present
@description
Checks the progress or completion state of a submitted reassignment.
@run
./kafka-reassign-partitions.sh --bootstrap-server localhost:9092 --reassignment-json-file reassignment.json --verify
@params
--reassignment-json-file | reassignment.json | Previously generated assignment plan
--verify | flag | Check current reassignment status
@end

@command Execute a partition reassignment
@mode MODERN
@since 2.6
@risk WARN
@requires
tool | service:kafka-reassign-partitions.sh | present
@description
Applies a replica-placement plan and starts moving partition data.
@run
./kafka-reassign-partitions.sh --bootstrap-server localhost:9092 --reassignment-json-file reassignment.json --execute
@params
--reassignment-json-file | reassignment.json | Reviewed assignment plan to apply
--execute | flag | Start the reassignment
@end

@command Trigger preferred leader election
@mode MODERN
@since 2.4
@risk WRITE
@requires
tool | service:kafka-leader-election.sh | present
@description
Moves eligible partition leadership back to preferred replicas.
@run
./kafka-leader-election.sh --bootstrap-server localhost:9092 --election-type preferred --all-topic-partitions
@params
--election-type | preferred | Elect preferred replicas as leaders
--all-topic-partitions | flag | Apply to every topic partition
@end


@group security

@command List all Kafka ACLs
@mode MODERN
@since 2.1
@requires
tool | service:kafka-acls.sh | present
@description
Displays access-control entries visible to the current Kafka identity.
@run
./kafka-acls.sh --bootstrap-server localhost:9092 --list
@end

@command List ACLs for one topic
@mode MODERN
@since 2.1
@requires
tool | service:kafka-acls.sh | present
@description
Displays access-control entries scoped to one topic resource.
@run
./kafka-acls.sh --bootstrap-server localhost:9092 --list --topic <topic_name>
@params
--topic | <topic_name> | Topic resource to inspect
@end

@command Add a consumer ACL
@mode MODERN
@since 2.1
@risk WRITE
@requires
tool | service:kafka-acls.sh | present
@description
Grants a principal consumer permissions for one topic and group.
@run
./kafka-acls.sh --bootstrap-server localhost:9092 --add --allow-principal User:<principal> --consumer --topic <topic_name> --group <consumer_group>
@params
--allow-principal | User:<principal> | Kafka identity receiving access
--topic | <topic_name> | Topic resource
--group | <consumer_group> | Consumer-group resource
@end

@command Remove matching ACLs
@mode MODERN
@since 2.1
@risk DELETE
@requires
tool | service:kafka-acls.sh | present
@description
Removes ACL entries matching the supplied principal and resource filters.
@run
./kafka-acls.sh --bootstrap-server localhost:9092 --remove --allow-principal User:<principal> --topic <topic_name>
@params
--allow-principal | User:<principal> | Kafka identity whose matching ACL is removed
--topic | <topic_name> | Topic resource filter
@end


@group native

@command Show kafka-topics native help
@mode MODERN
@since 0.8
@requires
tool | service:kafka-topics.sh | present
@description
Displays options supported by the installed topic tool.
@run
./kafka-topics.sh --help
@end

@command Show kafka-consumer-groups native help
@mode MODERN
@since 0.9
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Displays options supported by the installed consumer-group tool.
@run
./kafka-consumer-groups.sh --help
@end

@command Show kafka-console-consumer native help
@mode MODERN
@since 0.8
@requires
tool | service:kafka-console-consumer.sh | present
@description
Displays options supported by the installed console consumer.
@run
./kafka-console-consumer.sh --help
@end

@command Show kafka-console-producer native help
@mode MODERN
@since 0.8
@requires
tool | service:kafka-console-producer.sh | present
@description
Displays options supported by the installed console producer.
@run
./kafka-console-producer.sh --help
@end

@command Show kafka-configs native help
@mode MODERN
@since 0.10
@requires
tool | service:kafka-configs.sh | present
@description
Displays dynamic configuration and quota options.
@run
./kafka-configs.sh --help
@end

@command Show kafka-get-offsets native help
@mode MODERN
@since 3.0
@requires
tool | service:kafka-get-offsets.sh | present
@description
Displays raw topic-offset query options.
@run
./kafka-get-offsets.sh --help
@end

@command Show kafka-log-dirs native help
@mode MODERN
@since 1.0
@requires
tool | service:kafka-log-dirs.sh | present
@description
Displays broker log-directory inspection options.
@run
./kafka-log-dirs.sh --help
@end

@command Show kafka-broker-api-versions native help
@mode MODERN
@since 2.2
@requires
tool | service:kafka-broker-api-versions.sh | present
@description
Displays broker API compatibility query options.
@run
./kafka-broker-api-versions.sh --help
@end

@command Show kafka-reassign-partitions native help
@mode MODERN
@since 0.8
@requires
tool | service:kafka-reassign-partitions.sh | present
@description
Displays partition-reassignment generation, execution, and verification options.
@run
./kafka-reassign-partitions.sh --help
@end

@command Show kafka-leader-election native help
@mode MODERN
@since 2.4
@requires
tool | service:kafka-leader-election.sh | present
@description
Displays leader-election options supported by the installation.
@run
./kafka-leader-election.sh --help
@end

@command Show kafka-acls native help
@mode MODERN
@since 0.9
@requires
tool | service:kafka-acls.sh | present
@description
Displays Kafka ACL inspection and modification options.
@run
./kafka-acls.sh --help
@end

@command Show kafka-metadata-quorum native help
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-metadata-quorum.sh | present
@description
Displays KRaft controller-quorum operations.
@run
./kafka-metadata-quorum.sh --help
@end

@command Show kafka-features native help
@mode KRAFT
@since 2.7
@requires
tool | service:kafka-features.sh | present
@description
Displays cluster feature-version inspection and upgrade options.
@run
./kafka-features.sh --help
@end

@command Show kafka-metadata-shell native help
@mode KRAFT
@since 2.8
@requires
tool | service:kafka-metadata-shell.sh | present
@description
Displays local KRaft metadata-shell options.
@run
./kafka-metadata-shell.sh --help
@end

@command Show zookeeper-shell native help
@mode LEGACY-ZK
@since 0.8
@requires
tool | service:zookeeper-shell.sh | present
@description
Displays legacy ZooKeeper shell usage supported by the installation.
@run
./zookeeper-shell.sh
@end
