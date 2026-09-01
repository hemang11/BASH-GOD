@title Kubernetes commands

@description
A curated Kubernetes operator knowledge base for inspecting workloads, logs, configuration, events,
rollouts, cluster context, networking, and resource usage with native kubectl commands. Commands are
shown for review and, after BASH_GOD resolves a kubectl client and you confirm, can run through the
shared execution flow.

@discover
probe | kubectl | Client executable; presence marks a resolved kubectl installation
root | /usr/local/bin | Common manual and Intel Homebrew install directory
scan | /opt/homebrew | Bounded fallback for the Apple Silicon Homebrew layout
version | kubectl version --client | Prints only the client version and never contacts a cluster

@synced 1.37


@group pods

@command List pods in a namespace
@mode MODERN
@since 1.0
@description
Lists pod names, readiness, status, restart counts, and age in one namespace.
@run
kubectl get pods -n <namespace>
@params
-n | ontic-app | Namespace containing the pods
@optional
-l | app=ontic-app | Show only pods matching this label selector
@end

@command List pods with node and IP details
@mode MODERN
@since 1.0
@description
Adds pod IP, node assignment, nominated node, and readiness-gate columns to the pod list.
@run
kubectl get pods -n <namespace> -o wide
@params
-n | ontic-app | Namespace containing the pods
-o | wide | Include pod networking and node placement columns
@end

@command Watch pod status changes
@mode MODERN
@since 1.0
@description
Prints the current pod list and continues showing pod creation, deletion, and status changes.
@run
kubectl get pods -n <namespace> --watch
@params
-n | ontic-app | Namespace containing the pods
--watch | flag | Continue streaming resource changes until interrupted
@optional
-l | app=ontic-app | Watch only pods matching this label selector
@notes
Press Ctrl-C to stop watching.
@end


@group describe

@command Describe a pod
@mode MODERN
@since 1.0
@description
Shows pod conditions, container state, probes, mounts, scheduling details, and related events.
@run
kubectl describe pod <pod_name> -n <namespace>
@params
pod | <pod_name> | Pod to inspect
-n | ontic-app | Namespace containing the pod
@end

@command Describe a node
@mode MODERN
@since 1.0
@description
Shows node capacity, allocatable resources, conditions, taints, addresses, and scheduled pods.
@run
kubectl describe node <node_name>
@params
node | <node_name> | Cluster-scoped node to inspect
@end

@command Describe a deployment
@mode MODERN
@since 1.0
@description
Shows deployment strategy, replica state, pod template, conditions, and rollout events.
@run
kubectl describe deployment <deployment_name> -n <namespace>
@params
deployment | <deployment_name> | Deployment to inspect
-n | ontic-app | Namespace containing the deployment
@end

@command Describe a service
@mode MODERN
@since 1.0
@description
Shows the service selector, cluster IP, ports, traffic policy, and selected endpoints.
@run
kubectl describe service <service_name> -n <namespace>
@params
service | <service_name> | Service to inspect
-n | ontic-app | Namespace containing the service
@end


@group logs

@command Show pod logs
@mode MODERN
@since 1.0
@description
Prints the current logs from a pod's default container.
@run
kubectl logs <pod_name> -n <namespace>
@params
POD | <pod_name> | Pod whose logs should be displayed
-n | ontic-app | Namespace containing the pod
@optional
-c | <container_name> | Select one container in a multi-container pod
@end

@command Follow pod logs
@mode MODERN
@since 1.0
@description
Prints existing logs and continues streaming new lines from the selected pod.
@run
kubectl logs -f <pod_name> -n <namespace>
@params
-f | flag | Follow new log output until interrupted
POD | <pod_name> | Pod whose logs should be streamed
-n | ontic-app | Namespace containing the pod
@optional
-c | <container_name> | Select one container in a multi-container pod
@notes
Press Ctrl-C to stop following logs.
@end

@command Show logs from the previous container instance
@mode MODERN
@since 1.0
@description
Prints logs from the container instance that exited before the current restart.
@run
kubectl logs --previous <pod_name> -n <namespace>
@params
--previous | flag | Read the previously terminated container instance
POD | <pod_name> | Restarted pod to inspect
-n | ontic-app | Namespace containing the pod
@optional
-c | <container_name> | Select the restarted container in a multi-container pod
@end

@command Show the latest pod log lines
@mode MODERN
@since 1.0
@description
Prints only the newest log lines instead of the entire available container log.
@run
kubectl logs --tail=200 <pod_name> -n <namespace>
@params
--tail | 200 | Number of newest lines to display
POD | <pod_name> | Pod whose logs should be displayed
-n | ontic-app | Namespace containing the pod
@optional
--since | 10m | Include only logs newer than this duration
@end

@command Follow logs from pods matching a label
@mode MODERN
@since 1.25
@description
Streams labeled pods together and prefixes each line with its source pod and container.
@run
kubectl logs -f -l app=<label_value> -n <namespace> --all-containers=true --prefix=true
@params
-l | app=ontic-app | Label selector identifying the pods
-n | ontic-app | Namespace containing the pods
--all-containers | true | Include every container in each matching pod
--prefix | true | Prefix each line with the source pod and container
@notes
Press Ctrl-C to stop following logs.
@end


@group exec

@command Open a shell inside a pod
@mode MODERN
@since 1.0
@risk WARN
@description
Attaches an interactive shell to a running pod container for live troubleshooting.
@run
kubectl exec -it <pod_name> -n <namespace> -- sh
@params
-it | flags | Pass stdin and allocate a terminal
POD | <pod_name> | Pod whose container should open the shell
-n | ontic-app | Namespace containing the pod
-- | separator | Separates kubectl arguments from the container command
sh | command | Shell started inside the container
@optional
-c | <container_name> | Select one container in a multi-container pod
@notes
Commands entered after the shell opens run inside the container. Try bash only when the image provides it.
@end


@group configmaps

@command List ConfigMaps in a namespace
@mode MODERN
@since 1.0
@description
Lists ConfigMap names, data-key counts, and ages in one namespace.
@run
kubectl get configmaps -n <namespace>
@params
-n | ontic-app | Namespace containing the ConfigMaps
@end

@command Show a ConfigMap summary
@mode MODERN
@since 1.0
@description
Shows one ConfigMap's name, number of data entries, and age.
@run
kubectl get configmap <configmap_name> -n <namespace>
@params
configmap | <configmap_name> | ConfigMap to inspect
-n | ontic-app | Namespace containing the ConfigMap
@end

@command Show a complete ConfigMap as YAML
@mode MODERN
@since 1.0
@description
Prints metadata plus every data and binaryData entry from one ConfigMap.
@run
kubectl get configmap <configmap_name> -n <namespace> -o yaml
@params
configmap | <configmap_name> | ConfigMap to inspect
-n | ontic-app | Namespace containing the ConfigMap
-o | yaml | Render the complete resource as YAML
@end

@command Print one ConfigMap value
@mode MODERN
@since 1.0
@description
Prints only the value stored under one exact ConfigMap data key.
@run
kubectl get configmap <configmap_name> -n <namespace> -o go-template='{{ index .data "<key>" }}'
@params
configmap | <configmap_name> | ConfigMap to inspect
-n | ontic-app | Namespace containing the ConfigMap
<key> | application.properties | Exact data key whose value should be printed
@notes
The go-template index form also handles keys containing dots or dashes.
@end


@group events

@command List recent namespace events
@mode MODERN
@since 1.28
@description
Shows recent Normal and Warning events in the selected namespace.
@run
kubectl events -n <namespace>
@params
-n | ontic-app | Namespace whose recent events should be listed
@notes
If the installed kubectl does not provide the events subcommand, use the sorted-events command in this group.
@end

@command List events in creation order
@mode MODERN
@since 1.0
@description
Lists namespace events sorted by their creation timestamp so the latest activity appears last.
@run
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
@params
-n | ontic-app | Namespace whose events should be listed
--sort-by | .metadata.creationTimestamp | Sort events by creation time
@end

@command List recent warning events
@mode MODERN
@since 1.28
@description
Shows only recent Warning events, such as scheduling, image-pull, probe, and mount failures.
@run
kubectl events -n <namespace> --types=Warning
@params
-n | ontic-app | Namespace whose warning events should be listed
--types | Warning | Return only Warning events
@end

@command Show recent events for one pod
@mode MODERN
@since 1.28
@description
Filters recent events to those associated with one pod.
@run
kubectl events -n <namespace> --for pod/<pod_name>
@params
-n | ontic-app | Namespace containing the pod
--for | pod/<pod_name> | Pod whose events should be displayed
@end


@group deployments

@command List deployments in a namespace
@mode MODERN
@since 1.0
@description
Lists desired, current, available, and ready replica counts for deployments.
@run
kubectl get deployments -n <namespace>
@params
-n | ontic-app | Namespace containing the deployments
@end

@command Watch deployment rollout status
@mode MODERN
@since 1.0
@description
Waits while a deployment rollout progresses and reports whether it completes successfully.
@run
kubectl rollout status deployment/<deployment_name> -n <namespace>
@params
deployment | <deployment_name> | Deployment whose latest rollout should be watched
-n | ontic-app | Namespace containing the deployment
@optional
--timeout | 2m | Stop waiting after this duration
@end

@command Show deployment rollout history
@mode MODERN
@since 1.0
@description
Lists deployment revisions and recorded change causes.
@run
kubectl rollout history deployment/<deployment_name> -n <namespace>
@params
deployment | <deployment_name> | Deployment whose revisions should be listed
-n | ontic-app | Namespace containing the deployment
@optional
--revision | <revision_number> | Show details for one revision
@end


@group context

@command Show the current Kubernetes context
@mode MODERN
@since 1.0
@description
Prints the kubeconfig context currently used by kubectl.
@run
kubectl config current-context
@end

@command List configured Kubernetes contexts
@mode MODERN
@since 1.0
@description
Lists kubeconfig contexts with their clusters, users, namespaces, and current selection.
@run
kubectl config get-contexts
@end

@command Switch the current Kubernetes context
@mode MODERN
@since 1.0
@risk WRITE
@description
Changes the current context recorded in the local kubeconfig file.
@run
kubectl config use-context <context_name>
@params
CONTEXT | <context_name> | Exact context shown by kubectl config get-contexts
@notes
This changes only the local kubeconfig selection; verify the context before running cluster commands.
@end

@command List namespaces
@mode MODERN
@since 1.0
@description
Lists all namespaces visible to the current Kubernetes identity.
@run
kubectl get namespaces
@end

@command Show the current context namespace
@mode MODERN
@since 1.0
@description
Prints the namespace configured on the current context.
@run
kubectl config view --minify -o jsonpath='{..namespace}'
@params
--minify | flag | Keep only information used by the current context
-o | jsonpath={..namespace} | Print only the configured namespace value
@notes
No output means the context uses the default namespace.
@end


@group network

@command List services in a namespace
@mode MODERN
@since 1.0
@description
Lists service types, cluster IPs, external addresses, and exposed ports.
@run
kubectl get services -n <namespace>
@params
-n | ontic-app | Namespace containing the services
@end

@command List service endpoint slices
@mode MODERN
@since 1.21
@description
Lists the current EndpointSlice resources that connect services to backend addresses and ports.
@run
kubectl get endpointslices -n <namespace>
@params
-n | ontic-app | Namespace containing the EndpointSlices
@optional
-l | kubernetes.io/service-name=<service_name> | Select slices belonging to one service
@end

@command List legacy service Endpoints
@mode MODERN
@since 1.0
@description
Lists the older Endpoints objects that map services to backend addresses and ports.
@run
kubectl get endpoints -n <namespace>
@params
-n | ontic-app | Namespace containing the Endpoints objects
@notes
The Endpoints API is deprecated in Kubernetes 1.33 and later; prefer EndpointSlices on current clusters.
@end

@command List ingresses in a namespace
@mode MODERN
@since 1.0
@description
Lists ingress classes, hosts, addresses, ports, and ages.
@run
kubectl get ingresses -n <namespace>
@params
-n | ontic-app | Namespace containing the ingresses
@end

@command Forward a local port to a pod
@mode MODERN
@since 1.0
@risk WARN
@description
Keeps a local TCP port connected to one port in a selected pod for temporary access.
@run
kubectl port-forward pod/<pod_name> <local_port>:<pod_port> -n <namespace>
@params
pod | <pod_name> | Pod receiving the forwarded connection
<local_port> | 8080 | Port opened on localhost
<pod_port> | 8083 | Destination port inside the pod
-n | ontic-app | Namespace containing the pod
@notes
The listener binds to localhost by default and runs until interrupted with Ctrl-C; anyone with access to that local port can reach the selected pod port while it is open.
@end


@group usage

@command Show pod CPU and memory usage
@mode MODERN
@since 1.0
@description
Displays current CPU and memory usage for pods in one namespace.
@run
kubectl top pods -n <namespace>
@params
-n | ontic-app | Namespace containing the pods
@optional
--containers | flag | Show usage separately for every container
@notes
This requires the cluster metrics API, commonly provided by Metrics Server.
@end

@command Show node CPU and memory usage
@mode MODERN
@since 1.0
@description
Displays current CPU and memory usage and utilization percentages for every node.
@run
kubectl top nodes
@notes
This requires the cluster metrics API, commonly provided by Metrics Server.
@end


@group manifests

@command Preview manifest differences
@mode MODERN
@since 1.13
@description
Shows how a manifest differs from live resources without applying those changes.
@run
kubectl diff -f <manifest_file>
@params
-f | <manifest_file> | YAML or JSON manifest to compare with the cluster
@notes
kubectl diff exits with status 1 when differences are found and status greater than 1 on an error.
@end

@command Apply a manifest
@mode MODERN
@since 1.0
@risk WRITE
@description
Creates resources that do not exist and updates matching live resources from a manifest.
@run
kubectl apply -f <manifest_file>
@params
-f | <manifest_file> | YAML or JSON manifest whose resources should be applied
@notes
Review kubectl diff and verify the current context and namespace before applying the file.
@end


@group native

@command Show top-level kubectl native help
@mode MODERN
@since 1.0
@description
Displays kubectl commands and global options supported by the installed client.
@run
kubectl --help
@end

@command Show kubectl get native help
@mode MODERN
@since 1.0
@description
Displays resource listing, selectors, watching, and output-format options.
@run
kubectl get --help
@end

@command Show kubectl describe native help
@mode MODERN
@since 1.0
@description
Displays options for detailed resource descriptions and label selection.
@run
kubectl describe --help
@end

@command Show kubectl logs native help
@mode MODERN
@since 1.0
@description
Displays log selection, container, time-range, follow, and output options.
@run
kubectl logs --help
@end

@command Show kubectl exec native help
@mode MODERN
@since 1.0
@description
Displays container selection, terminal, and remote-command options.
@run
kubectl exec --help
@end

@command Show kubectl events native help
@mode MODERN
@since 1.28
@description
Displays event filtering, resource selection, and watch options.
@run
kubectl events --help
@end

@command Show kubectl rollout native help
@mode MODERN
@since 1.0
@description
Displays deployment rollout status, history, restart, pause, resume, and undo operations.
@run
kubectl rollout --help
@end

@command Show kubectl config native help
@mode MODERN
@since 1.0
@description
Displays kubeconfig context, cluster, user, and preference operations.
@run
kubectl config --help
@end

@command Show kubectl port-forward native help
@mode MODERN
@since 1.0
@description
Displays supported resource targets, port mappings, and listener-address options.
@run
kubectl port-forward --help
@end

@command Show kubectl apply native help
@mode MODERN
@since 1.0
@description
Displays manifest input, validation, dry-run, field-management, and apply options.
@run
kubectl apply --help
@end

@command Explain a Kubernetes resource schema
@mode MODERN
@since 1.0
@description
Displays fields and descriptions for one resource type using the cluster's API schema.
@run
kubectl explain <resource_type>
@params
RESOURCE | <resource_type> | Resource type such as pod, deployment, or service
@optional
--recursive | flag | Include all nested fields in the schema output
@end
