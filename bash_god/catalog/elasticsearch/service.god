@title Elasticsearch commands

@description
Curated Elasticsearch host checks and read-only REST API operations. A plain interactive search
lets an operator review, edit, and explicitly run a selected command through tools on PATH.

@execution PATH


@group service

@command Check the Elasticsearch HTTP endpoint
@mode MODERN
@description
Returns the cluster name, node name, and Elasticsearch version when the local HTTP endpoint responds.
@run
curl -sS 'http://localhost:9200/'
@params
URL | http://localhost:9200/ | Elasticsearch HTTP endpoint; replace the host or port when needed
@end

@command Check the Elasticsearch systemd service
@mode LOCAL
@description
Shows whether the local Elasticsearch systemd unit is active and includes recent status lines.
@run
systemctl status elasticsearch --no-pager
@params
elasticsearch | service name | Default Elasticsearch package service unit
@end

@command Find the Elasticsearch process
@mode LOCAL
@description
Lists matching Elasticsearch processes with their full command lines.
@run
pgrep -af elasticsearch
@end

@command Check which process listens on port 9200
@mode LOCAL
@description
Shows the process currently accepting Elasticsearch HTTP connections on the default port.
@run
lsof -nP -iTCP:9200 -sTCP:LISTEN
@params
9200 | default HTTP port | Port commonly used by the Elasticsearch REST API
@end

@command Show recent Elasticsearch service logs
@mode LOCAL
@description
Displays the latest one hundred journal entries for the local Elasticsearch service.
@run
journalctl -u elasticsearch -n 100 --no-pager
@params
-n | 100 | Number of recent journal entries to display
@end

@command Show the packaged Elasticsearch configuration
@mode LOCAL
@description
Displays the common package-install location for elasticsearch.yml.
@run
cat /etc/elasticsearch/elasticsearch.yml
@notes
Archive and custom installations may keep elasticsearch.yml under a different config directory.
@end


@group cluster

@command Show cluster health
@mode MODERN
@description
Shows green, yellow, or red health plus shard and node counts.
@run
curl -sS 'http://localhost:9200/_cluster/health?pretty'
@params
_cluster/health | API path | Cluster-wide health summary
@end

@command Show a compact cluster health row
@mode MODERN
@description
Prints a human-readable one-line health summary through the CAT API.
@run
curl -sS 'http://localhost:9200/_cat/health?v=true'
@params
v=true | query option | Include column headings
@end

@command List cluster nodes and resource pressure
@mode MODERN
@description
Shows node roles, elected master, heap, memory, CPU, load, and node name.
@run
curl -sS 'http://localhost:9200/_cat/nodes?v=true&h=ip,heap.percent,ram.percent,cpu,load_1m,node.role,master,name'
@params
h | selected columns | Limits output to the most useful node-health fields
@end

@command Show cluster-wide statistics
@mode MODERN
@description
Returns aggregate node, index, shard, storage, JVM, and operating-system statistics.
@run
curl -sS 'http://localhost:9200/_cluster/stats?pretty'
@end


@group indices

@command List indices
@mode MODERN
@description
Shows index health, status, shard counts, document counts, and storage size.
@run
curl -sS 'http://localhost:9200/_cat/indices?v=true&s=index'
@params
s=index | sort option | Sort rows alphabetically by index name
@end

@command Find the largest indices
@mode MODERN
@description
Sorts indices by total store size so the largest indices appear first.
@run
curl -sS 'http://localhost:9200/_cat/indices?v=true&s=store.size:desc&h=health,status,index,docs.count,store.size,pri.store.size'
@params
s=store.size:desc | sort option | Sort descending by primary-plus-replica storage
@end

@command Describe one index
@mode MODERN
@description
Shows health, shard counts, document counts, and storage for one index or index pattern.
@run
curl -sS 'http://localhost:9200/_cat/indices/<index_name>?v=true'
@params
<index_name> | orders-* | Index name, alias target, or wildcard pattern to inspect
@end

@command List aliases
@mode MODERN
@description
Shows aliases and the indices to which they currently point.
@run
curl -sS 'http://localhost:9200/_cat/aliases?v=true&s=alias,index'
@end

@command Show an index mapping
@mode MODERN
@description
Displays field types and mapping options for one index.
@run
curl -sS 'http://localhost:9200/<index_name>/_mapping?pretty'
@params
<index_name> | orders-v1 | Index whose field mapping should be inspected
@end

@command Show index settings
@mode MODERN
@description
Displays shard, replica, refresh, analysis, and other settings for one index.
@run
curl -sS 'http://localhost:9200/<index_name>/_settings?pretty'
@params
<index_name> | orders-v1 | Index whose settings should be inspected
@end


@group shards

@command List all shards
@mode MODERN
@description
Shows every primary and replica shard, its state, size, node, and allocation.
@run
curl -sS 'http://localhost:9200/_cat/shards?v=true&s=index,shard,prirep'
@end

@command Find unassigned shards
@mode MODERN
@description
Filters the shard table to rows that are currently unassigned.
@run
curl -sS 'http://localhost:9200/_cat/shards?v=true&h=index,shard,prirep,state,unassigned.reason,node' | awk '$4 == "UNASSIGNED" || NR == 1'
@params
state | UNASSIGNED | Shard state selected by the local output filter
@end

@command Explain an unassigned shard
@mode MODERN
@description
Asks Elasticsearch to explain why one currently unassigned shard cannot be allocated.
@run
curl -sS 'http://localhost:9200/_cluster/allocation/explain?pretty'
@notes
With no request body, Elasticsearch selects the first unassigned shard it finds.
@end

@command Show shard allocation and free disk
@mode MODERN
@description
Shows shard counts and disk usage for each data node.
@run
curl -sS 'http://localhost:9200/_cat/allocation?v=true&s=disk.percent:desc'
@end

@command Show shard recovery progress
@mode MODERN
@description
Shows active and recently completed shard recoveries with stage and percentage progress.
@run
curl -sS 'http://localhost:9200/_cat/recovery?v=true&active_only=true'
@params
active_only=true | query option | Limit the table to recoveries still in progress
@end


@group search

@command Read a small sample of documents
@mode MODERN
@description
Returns at most ten documents from one index without changing them.
@run
curl -sS -H 'Content-Type: application/json' -X POST 'http://localhost:9200/<index_name>/_search?pretty' -d '{"size":10,"query":{"match_all":{}}}'
@params
<index_name> | orders-v1 | Index or alias to search
size | 10 | Maximum number of hits returned
@end

@command Search one field for a value
@mode MODERN
@description
Runs a match query against one field and returns up to ten matching documents.
@run
curl -sS -H 'Content-Type: application/json' -X POST 'http://localhost:9200/<index_name>/_search?pretty' -d '{"size":10,"query":{"match":{"<field_name>":"<search_value>"}}}'
@params
<field_name> | status | Mapped field to search
<search_value> | ready | Value analyzed by the match query
size | 10 | Maximum number of hits returned
@end

@command Count documents in an index
@mode MODERN
@description
Returns the logical document count for one index or alias.
@run
curl -sS 'http://localhost:9200/<index_name>/_count?pretty'
@params
<index_name> | orders-v1 | Index or alias whose documents should be counted
@end

@command Get one document by ID
@mode MODERN
@description
Retrieves one document directly when both its index and identifier are known.
@run
curl -sS 'http://localhost:9200/<index_name>/_doc/<document_id>?pretty'
@params
<index_name> | orders-v1 | Index containing the document
<document_id> | asset-123 | Exact document identifier
@end


@group performance

@command Show node JVM and filesystem statistics
@mode MODERN
@description
Returns per-node JVM heap, garbage-collection, process, and filesystem metrics.
@run
curl -sS 'http://localhost:9200/_nodes/stats/jvm,process,fs?pretty'
@params
jvm,process,fs | metrics | Restrict the large node-stats response to core runtime resources
@end

@command Show hot threads
@mode MODERN
@description
Captures stack traces from the busiest Elasticsearch threads for CPU troubleshooting.
@run
curl -sS 'http://localhost:9200/_nodes/hot_threads'
@end

@command List running cluster tasks
@mode MODERN
@description
Shows long-running searches, reindex jobs, recoveries, and other active tasks.
@run
curl -sS 'http://localhost:9200/_cat/tasks?v=true&s=running_time:desc'
@end

@command List pending cluster-state tasks
@mode MODERN
@description
Shows cluster-level changes waiting for the elected master to process them.
@run
curl -sS 'http://localhost:9200/_cat/pending_tasks?v=true'
@end


@group native

@command List available CAT API routes
@mode MODERN
@description
Displays the human-oriented CAT endpoints exposed by the connected Elasticsearch version.
@run
curl -sS 'http://localhost:9200/_cat'
@end

@command Show columns supported by a CAT endpoint
@mode MODERN
@description
Displays every column name and description supported by one CAT endpoint.
@run
curl -sS 'http://localhost:9200/_cat/<cat_endpoint>?help=true'
@params
<cat_endpoint> | indices | CAT route whose supported columns should be listed
@end

@command Show native curl help
@mode LOCAL
@description
Displays the locally installed curl options used to call Elasticsearch REST APIs.
@run
curl --help all
@end
