@title MongoDB commands

@description
A curated MongoDB operator knowledge base covering local service checks, shell connections,
replica-set health, database and collection inspection, common queries, live operations, backup,
restore, and native tool help. BASH_GOD prefers a modern mongosh installation and can fall back to
the legacy mongo shell when that is the client the catalog finds. Shell expressions are launched
through the selected client with --eval, so the picker always presents an executable command. The
detected client version applies only to direct shell command-line records; it does not establish MongoDB server or MongoDB
Database Tools compatibility. Replace every placeholder before using a command; no example
contains credentials.

@discover
probe | mongosh | Preferred modern MongoDB Shell executable
probe | mongo | Legacy MongoDB shell fallback when mongosh is absent
root | /usr/local/bin | Common Unix package-manager bin directory
scan | /opt | Bounded scan root for package-managed MongoDB Shell installations
version | <probe> --version | Reads the selected shell client version without connecting to a deployment

@connection ENDPOINT 27017


@group service

@command Check whether the MongoDB service is running
@mode LOCAL
@since 0.0
@description
Shows the current systemd status and recent status details for the local mongod service.
@run
systemctl status mongod
@params
SERVICE | mongod | Common MongoDB systemd unit name
@notes
Some distributions name the unit mongodb instead of mongod; confirm the installed unit name when this one is absent.
@end

@command Find the running mongod process
@mode LOCAL
@since 0.0
@description
Shows the MongoDB server process and its launch arguments without matching the pgrep command itself.
@run
pgrep -af '[m]ongod'
@end

@command Check whether the MongoDB listener port is open
@mode LOCAL
@since 0.0
@description
Shows the process listening on the default MongoDB TCP port.
@run
ss -ltnp | grep ':27017'
@params
PORT | 27017 | Default mongod client port; replace it when net.port differs
@end

@command Show recent MongoDB service logs
@mode LOCAL
@since 0.0
@description
Displays the latest systemd journal entries for the local mongod service.
@run
journalctl -u mongod -n 200 --no-pager
@params
-u | mongod | MongoDB systemd unit name
-n | 200 | Number of recent journal lines
@end


@group connect

@command Connect with mongosh
@mode MODERN
@since 0.0
@description
Opens the modern MongoDB shell against one host, port, and database without embedding credentials.
@run
mongosh "mongodb://<host>:27017/<database>"
@params
HOST | <host> | Resolvable MongoDB hostname
PORT | 27017 | MongoDB listener port
DATABASE | <database> | Initial database selected after connecting
@notes
This opens an interactive database shell; review the target because later shell input can change data.
@end

@command Connect with mongosh and an authentication prompt
@mode MODERN
@since 0.0
@description
Connects as one user and asks for the password interactively instead of exposing it in shell history.
@run
mongosh "mongodb://<host>:27017/<database>" --username <username> --authenticationDatabase <auth_database>
@params
--username | <username> | MongoDB user name; mongosh prompts for its password
--authenticationDatabase | <auth_database> | Database where the user was created, commonly admin
DATABASE | <database> | Database to inspect after authentication
@notes
Do not add a password to the URI or command line; use the hidden interactive prompt. Review the target because later shell input can change data.
@end

@command Ping MongoDB with mongosh
@mode MODERN
@since 0.0
@description
Runs the read-only ping command and exits, confirming that the server accepts a shell connection.
@run
mongosh "mongodb://<host>:27017/admin" --quiet --eval 'db.runCommand({ ping: 1 })'
@params
--quiet | flag | Suppress the shell banner
--eval | db.runCommand({ ping: 1 }) | Execute the MongoDB ping command and exit
@end

@command Connect with the legacy mongo shell
@mode MODERN
@since 0.0
@description
Opens the older mongo shell on hosts where mongosh is not installed.
@run
mongo --host <host> --port 27017 <database>
@params
--host | <host> | Resolvable MongoDB hostname
--port | 27017 | MongoDB listener port
DATABASE | <database> | Initial database selected after connecting
@notes
The mongo shell is legacy and is absent from newer MongoDB packages; prefer mongosh when it is available. Review the target because later shell input can change data.
@end

@command Ping MongoDB with the legacy mongo shell
@mode MODERN
@since 0.0
@description
Runs the read-only ping command through the older mongo shell and exits.
@run
mongo --host <host> --port 27017 admin --quiet --eval 'db.runCommand({ ping: 1 })'
@params
--host | <host> | Resolvable MongoDB hostname
--port | 27017 | MongoDB listener port
--eval | db.runCommand({ ping: 1 }) | Execute the MongoDB ping command and exit
@notes
Use the mongosh form on current installations.
@end


@group replica

@command Show replica-set status
@mode MODERN
@since 0.0
@description
Shows the current member's view of replica-set health, states, heartbeats, elections, and optimes.
@run
mongosh --quiet --eval 'rs.status()'
@notes
Runs against the selected shell's normal connection target; use a replica-set member.
@end

@command Show replica-set configuration
@mode MODERN
@since 0.0
@description
Displays the replica-set configuration, including member hosts, votes, priorities, and settings.
@run
mongosh --quiet --eval 'rs.conf()'
@notes
Runs against the selected shell's normal connection target; use a replica-set member.
@end

@command Summarize replica-set members
@mode MODERN
@since 0.0
@description
Returns a compact runtime view of each member's identity, state, health, and latest applied operation time.
@run
mongosh --quiet --eval 'rs.status().members.map(function(m) { return { id: m._id, name: m.name, state: m.stateStr, health: m.health, optime: m.optimeDate }; })'
@notes
health 1 means the member is reachable from the member where this command runs; inspect state and optime together.
@end

@command Show secondary replication lag
@mode MODERN
@since 0.0
@description
Prints each secondary's synchronization source, last applied operation time, and estimated lag.
@run
mongosh --quiet --eval 'rs.printSecondaryReplicationInfo()'
@notes
Run on the primary when possible so every secondary can be compared against the same reference point.
@end

@command Show the oplog time window
@mode MODERN
@since 0.0
@description
Prints the configured oplog size and the time range currently retained on this replica-set member.
@run
mongosh --quiet --eval 'rs.printReplicationInfo()'
@notes
The oplog window should comfortably exceed the longest expected secondary outage or replication delay.
@end


@group inspect

@command List databases
@mode MODERN
@since 0.0
@description
Lists the databases visible to the current MongoDB user.
@run
mongosh --quiet --eval 'db.adminCommand({ listDatabases: 1 })'
@notes
Runs against the selected shell's normal connection target.
@end

@command List collections
@mode MODERN
@since 0.0
@description
Lists collections and views visible in the current database.
@run
mongosh --quiet --eval 'db.getCollectionNames()'
@notes
Runs against the selected shell's normal connection target.
@end

@command Show collection metadata
@mode MODERN
@since 0.0
@description
Displays one collection's type, options, validator, and other catalog metadata.
@run
mongosh --quiet --eval 'db.getCollectionInfos({ name: "<collection_name>" })'
@params
name | <collection_name> | Exact collection name to inspect
@notes
Runs against the selected shell's normal connection target.
@end

@command List collection indexes
@mode MODERN
@since 0.0
@description
Shows every index definition, key pattern, name, and configured index option for one collection.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").getIndexes()'
@params
COLLECTION | <collection_name> | Collection whose indexes should be inspected
@notes
Runs against the selected shell's normal connection target.
@end

@command Show database size and object statistics
@mode MODERN
@since 0.0
@description
Shows collection, document, storage, and index totals for the current database in mebibytes.
@run
mongosh --quiet --eval 'db.stats({ scale: 1024 * 1024 })'
@params
scale | 1024 * 1024 | Divide byte-based size fields into mebibytes
@notes
Runs against the selected shell's normal connection target.
@end

@command Show collection size and storage statistics
@mode MODERN
@since 0.0
@description
Shows document count, logical size, allocated storage, and index totals for one collection in mebibytes.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").stats({ scale: 1024 * 1024 })'
@params
COLLECTION | <collection_name> | Collection whose storage should be inspected
scale | 1024 * 1024 | Divide byte-based size fields into mebibytes
@notes
Runs against the selected shell's normal connection target.
@end


@group query

@command Select a database
@mode MODERN
@since 0.0
@description
Opens the selected MongoDB client directly in one database so subsequent work starts in that context.
@run
mongosh "mongodb://<host>:27017/<database>"
@params
HOST | <host> | Resolvable MongoDB hostname
DATABASE | <database> | Database to use after connecting
@notes
This opens an interactive shell; exit returns to BASH_GOD without creating a database unless data is written.
@end

@command Find matching documents with a limit
@mode MODERN
@since 0.0
@description
Finds documents containing one exact field value and returns at most twenty results.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").find({ "<field>": "<value>" }).limit(20)'
@params
COLLECTION | <collection_name> | Collection to query
FIELD | <field> | Document field used by the filter
VALUE | <value> | Exact value that the field must equal
limit | 20 | Maximum documents returned to the shell
@optional
maxTimeMS() | 5000 | Add .maxTimeMS(5000) to stop server work after five seconds
@notes
Runs against the selected shell's normal connection target.
@end

@command Find one document by ObjectId
@mode MODERN
@since 0.0
@description
Looks up one document by its standard MongoDB _id ObjectId value.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").findOne({ _id: ObjectId("<object_id>") })'
@params
COLLECTION | <collection_name> | Collection to query
ObjectId | <object_id> | Twenty-four-character hexadecimal ObjectId string
@notes
Runs against the selected shell's normal connection target.
@end

@command Return only selected fields
@mode MODERN
@since 0.0
@description
Filters documents and projects only the requested field while excluding _id.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").find({ "<field>": "<value>" }, { "<field_to_return>": 1, _id: 0 }).limit(20)'
@params
FILTER | "<field>": "<value>" | Exact field-value condition
PROJECTION | "<field_to_return>": 1 | Include this field in each result
_id | 0 | Exclude the _id field from each result
@notes
Runs against the selected shell's normal connection target.
@end

@command Show the newest documents
@mode MODERN
@since 0.0
@description
Sorts one collection by a timestamp field in descending order and returns the latest twenty documents.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").find({}).sort({ "<timestamp_field>": -1 }).limit(20)'
@params
COLLECTION | <collection_name> | Collection to query
TIMESTAMP_FIELD | <timestamp_field> | Date or sortable sequence field
sort | -1 | Descending order so newest values appear first
limit | 20 | Maximum documents returned
@notes
Runs against the selected shell's normal connection target.
@end

@command Count matching documents
@mode MODERN
@since 0.0
@description
Returns an exact count of documents matching one field-value condition.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").countDocuments({ "<field>": "<value>" })'
@params
COLLECTION | <collection_name> | Collection to count
FILTER | "<field>": "<value>" | Condition documents must match
@notes
Runs against the selected shell's normal connection target.
@end

@command Search a string field with a case-insensitive regular expression
@mode MODERN
@since 0.0
@description
Finds up to twenty documents whose selected field matches a case-insensitive regular expression.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").find({ "<field>": { $regex: "<pattern>", $options: "i" } }).limit(20)'
@params
$regex | <pattern> | Regular expression applied to the selected field
$options | i | Make matching case-insensitive
limit | 20 | Maximum documents returned
@notes
An unanchored regular expression can scan many documents; inspect indexes and narrow the pattern on large collections.
@end

@command Explain a query with execution statistics
@mode MODERN
@since 0.0
@description
Shows the winning plan, index usage, documents examined, keys examined, and execution timing for a find query.
@run
mongosh --quiet --eval 'db.getCollection("<collection_name>").explain("executionStats").find({ "<field>": "<value>" })'
@params
executionStats | mode | Execute the read query and include runtime statistics
FILTER | "<field>": "<value>" | Query whose plan should be inspected
@notes
This executes the read query to measure it but does not modify documents.
@end


@group health

@command Show complete MongoDB server status
@mode MODERN
@since 0.0
@description
Returns a broad snapshot of process state, memory, connections, network traffic, locks, and storage-engine metrics.
@run
mongosh --quiet --eval 'db.serverStatus()'
@notes
The output is large; use the focused rows in this group when only one metric family is needed.
@end

@command Show MongoDB connection usage
@mode MODERN
@since 0.0
@description
Displays current, available, active, and rejected client connection counters.
@run
mongosh --quiet --eval 'db.serverStatus().connections'
@notes
Runs against the selected shell's normal connection target.
@end

@command Show active MongoDB operations
@mode MODERN
@since 0.0
@description
Lists database operations that are currently active on the connected server.
@run
mongosh --quiet --eval 'db.currentOp({ active: true })'
@notes
Viewing every user's operations requires the inprog privilege; without it, use db.currentOp({ $ownOps: true }) for your own operations.
@end

@command Find long-running operations for one database
@mode MODERN
@since 0.0
@description
Lists active operations running longer than five seconds in one database namespace.
@run
mongosh --quiet --eval 'db.currentOp({ active: true, secs_running: { $gt: 5 }, ns: /^<database>\./ })'
@params
$gt | 5 | Minimum elapsed runtime in seconds
ns | /^<database>\./ | Match namespaces belonging to this database
@notes
This only inspects operations; it does not terminate them.
@end


@group backup

@command Dump one database
@mode MODERN
@since 0.0
@risk WRITE
@description
Creates a BSON dump directory containing all collections and metadata from one database.
@run
mongodump --host <host> --port 27017 --db <database> --out <output_directory>
@params
--host | <host> | MongoDB host to read
--port | 27017 | MongoDB listener port
--db | <database> | Database to dump
--out | <output_directory> | Parent directory where mongodump writes database files
@optional
--username | <username> | Authenticate as this user and receive a password prompt
--authenticationDatabase | <auth_database> | Database where that user was created
@notes
mongodump reads server data but writes local files and can affect the working set; choose an output directory deliberately.
@end

@command Dump one collection
@mode MODERN
@since 0.0
@risk WRITE
@description
Creates a BSON dump for one collection instead of every collection in the database.
@run
mongodump --host <host> --port 27017 --db <database> --collection <collection_name> --out <output_directory>
@params
--host | <host> | MongoDB host to read
--port | 27017 | MongoDB listener port
--db | <database> | Database containing the collection
--collection | <collection_name> | Exact collection to dump
--out | <output_directory> | Parent directory, not an individual output filename
@notes
The BSON file is written below <output_directory>/<database>/ using the collection name.
@end

@command Dump one database to a compressed archive
@mode MODERN
@since 0.0
@risk WRITE
@description
Writes one database and its metadata into a single gzip-compressed archive file.
@run
mongodump --host <host> --port 27017 --db <database> --archive=<archive_file> --gzip
@params
--db | <database> | Database to dump
--archive | <archive_file> | Single output archive path, commonly ending in .gz
--gzip | flag | Compress the archive generated by mongodump
@end

@command Preview restoring one database
@mode MODERN
@since 0.0
@description
Shows what mongorestore would read for one database without importing any data.
@run
mongorestore --host <host> --port 27017 --nsInclude '<database>.*' --dryRun --verbose <dump_directory>
@params
--nsInclude | <database>.* | Include every collection in the selected database
--dryRun | flag | Return restore summary information without importing data
--verbose | flag | Show detailed preview information
PATH | <dump_directory> | Root directory created by mongodump
@end

@command Restore one database from a dump directory
@mode MODERN
@since 0.0
@risk WRITE
@description
Imports every dumped collection from one database namespace into the target MongoDB deployment.
@run
mongorestore --host <host> --port 27017 --nsInclude '<database>.*' <dump_directory>
@params
--host | <host> | Target MongoDB host that will receive data
--port | 27017 | Target MongoDB listener port
--nsInclude | <database>.* | Restore every dumped collection in this database namespace
PATH | <dump_directory> | Root directory created by mongodump
@optional
--username | <username> | Authenticate as this user and receive a password prompt
--authenticationDatabase | <auth_database> | Database where that user was created
--stopOnError | flag | Stop on duplicate-key or document-validation errors
@notes
Run the preview row first. This inserts data and can create missing databases or collections; existing matching documents are not removed unless an explicit destructive option such as --drop is added.
@end

@command Restore one collection from a dump directory
@mode MODERN
@since 0.0
@risk WRITE
@description
Imports one dumped collection selected by its complete database and collection namespace.
@run
mongorestore --host <host> --port 27017 --nsInclude '<database>.<collection_name>' <dump_directory>
@params
--host | <host> | Target MongoDB host that will receive data
--port | 27017 | Target MongoDB listener port
--nsInclude | <database>.<collection_name> | Exact namespace to restore
PATH | <dump_directory> | Root directory created by mongodump
@notes
This writes documents to the target and can create a missing collection. Current database tools prefer --nsInclude over the deprecated --db and --collection restore flags for directories and archives.
@end

@command Restore one database from a compressed archive
@mode MODERN
@since 0.0
@risk WRITE
@description
Imports one database namespace from a gzip-compressed mongodump archive.
@run
mongorestore --host <host> --port 27017 --archive=<archive_file> --gzip --nsInclude '<database>.*'
@params
--archive | <archive_file> | Compressed archive created by mongodump
--gzip | flag | Decompress the archive while restoring
--nsInclude | <database>.* | Restore every collection in the selected database namespace
@notes
This inserts data and can create missing databases or collections. Use the same --archive, --gzip, and --nsInclude options with --dryRun --verbose to preview the archive first.
@end


@group native

@command Show MongoDB shell command-line help
@mode MODERN
@since 0.0
@description
Displays connection, authentication, script, output, TLS, and other options supported by the selected MongoDB shell.
@run
mongosh --help
@end

@command Show MongoDB database shell help
@mode MODERN
@since 0.0
@description
Lists the database methods available through the selected MongoDB shell.
@run
mongosh --quiet --eval 'db.help()'
@notes
Runs against the selected shell's normal connection target.
@end

@command Show mongodump native help
@mode MODERN
@since 0.0
@description
Displays every backup, connection, authentication, namespace, and output option supported by the installed mongodump version.
@run
mongodump --help
@end

@command Show mongorestore native help
@mode MODERN
@since 0.0
@description
Displays every restore, connection, namespace, conflict-handling, and input option supported by the installed mongorestore version.
@run
mongorestore --help
@end
