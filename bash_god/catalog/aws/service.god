@title AWS commands

@description
Curated AWS CLI knowledge for identity checks, EC2 instance-profile credentials, Systems Manager
sessions, instance metadata, and read-only Route 53 inventory. Commands are shown for review and,
after BASH_GOD resolves the AWS CLI and you confirm, can run through the shared execution flow.

@discover
probe | aws | AWS CLI executable; presence marks a resolved AWS CLI installation
root | /usr/local/bin | Common AWS CLI v2, manual, and Intel Homebrew binary directory
scan | /usr/local | Bounded fallback for the AWS CLI v2 bundled install layout
version | aws --version | Prints the AWS CLI version; generic discovery captures stdout and stderr

@connection CONTEXT

@synced 2.36.34


@group identity

@command Show the current AWS identity
@mode MODERN
@since 1.16.12
@description
Displays the account, principal ARN, and user ID used by subsequent AWS CLI commands.
@run
aws sts get-caller-identity
@end


@group ec2

@command Show the IAM instance profile attached to an instance
@mode MODERN
@since 1.16.12
@description
Shows which IAM instance profile is currently associated with an EC2 instance, along with the association ID and state.
@run
aws ec2 describe-iam-instance-profile-associations --filters Name=instance-id,Values=<instance_id> --output table
@params
--filters | Name=instance-id,Values=<instance_id> | Restrict associations to one EC2 instance
--output | table | Render association ID, instance ID, profile ARN, and state as a table
@notes
An empty result means the instance has no role, so AWS CLI calls made on it fall back to exported environment variables or a credentials file.
@end

@command Attach an IAM instance profile to an instance
@mode MODERN
@since 1.16.12
@risk WRITE
@description
Associates an IAM instance profile with an EC2 instance so every user on that host receives short-lived role credentials from instance metadata instead of exported access keys.
@run
aws ec2 associate-iam-instance-profile --instance-id <instance_id> --iam-instance-profile Name=<instance_profile_name>
@params
--instance-id | <instance_id> | EC2 instance that will receive the role
--iam-instance-profile | Name=<instance_profile_name> | Instance profile to attach; use Arn=<profile_arn> when the name is ambiguous
@notes
This changes IAM state and grants every process on the instance the role's permissions, so confirm the profile's scope with the account owner before running it. An instance that already holds an association needs aws ec2 replace-iam-instance-profile-association instead.
@end


@group ssm

@command Open a Session Manager shell on an instance
@mode MODERN
@since 1.16.12
@risk WARN
@description
Starts an interactive Systems Manager session on an EC2 instance without SSH, an open inbound port, or a key pair.
@run
aws ssm start-session --target <instance_id>
@params
--target | <instance_id> | EC2 instance registered as a managed node running the SSM agent
@optional
--region | <aws_region> | Region holding the instance when it differs from the configured default
@notes
Requires the Session Manager plugin and the target's Session Manager permissions. This opens an interactive shell on the remote instance; use Ctrl-C to end the session.
@end

@command Open a Session Manager shell as a specific host user
@mode MODERN
@since 1.16.12
@risk WARN
@description
Starts a Systems Manager session that lands directly in another host account's login shell, avoiding a manual user switch after connecting.
@run
aws ssm start-session --target <instance_id> --document-name AWS-StartInteractiveCommand --parameters command="sudo -u <host_user> -i"
@params
--document-name | AWS-StartInteractiveCommand | Session document that runs one interactive command instead of the default shell
--parameters | command="sudo -u <host_user> -i" | Interactive command opening the target user's login shell
@notes
Requires the Session Manager plugin and permission to start the session. This starts a remote sudo login shell as the selected host user; use Ctrl-C to end the session and verify the target before connecting.
@end


@group imds

@command Show the IAM role served by instance metadata
@mode LOCAL
@since 0.0
@risk WARN
@description
Reports the instance profile ARN and role that the metadata service is serving on an EC2 host, which is where the AWS CLI finds credentials when no environment variables or credentials file exist.
@run
curl -s http://169.254.169.254/latest/meta-data/iam/info
@notes
This unauthenticated IMDSv1 form returns 401 on an instance that enforces IMDSv2. It returns role metadata, not credentials; do not change the path to retrieve secret credential material unless you are authorized to handle it.
@end

@command Show the metadata role name through an IMDSv2 token
@mode LOCAL
@since 0.0
@risk WARN
@description
Requests a metadata session token and lists the role name whose short-lived credentials the metadata service is serving on an instance that enforces IMDSv2.
@run
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60") && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
@params
-X PUT | /latest/api/token | Request the session token that IMDSv2 requires before any metadata read
-H | X-aws-ec2-metadata-token-ttl-seconds: 60 | Token lifetime in seconds
@notes
The shown request returns only a role name and keeps the short-lived IMDSv2 token inside this command. Do not change the URL to retrieve credentials unless you are authorized to handle secret output; never paste access keys or session tokens into a ticket, log, or chat.
@end

@command Verify the instance role without exported keys
@mode LOCAL
@since 0.0
@description
Runs one identity query with exported credential variables removed, proving whether the AWS CLI can fall back to an attached instance role or another lower-priority credential source.
@run
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN aws sts get-caller-identity
@notes
This leaves the caller's environment unchanged. The credential chain prefers environment variables, then ~/.aws/credentials, then instance metadata, so exported keys can mask an attached role until they are omitted for this one command.
@end


@group route53

@command List Route 53 hosted zones
@mode MODERN
@since 1.16.12
@description
Lists every hosted-zone ID and DNS name visible to the current AWS account identity.
@run
aws route53 list-hosted-zones --output table
@optional
--query | HostedZones[?Config.PrivateZone] | Narrow the table to private zones when an account holds both kinds
@end

@command List the records in a hosted zone
@mode MODERN
@since 1.16.12
@description
Lists the record names, types, and values held in one Route 53 hosted zone.
@run
aws route53 list-resource-record-sets --hosted-zone-id <hosted_zone_id> --output table
@params
--hosted-zone-id | <hosted_zone_id> | Route 53 hosted-zone identifier from the zone list
@notes
Route 53 returns fully qualified names with a trailing dot. Pipe to grep when hunting one hostname.
@end


@group native

@command Show AWS CLI native help
@mode MODERN
@since 1.16.12
@description
Displays the installed AWS CLI's top-level services and global options.
@run
aws help
@end

@command Show AWS STS native help
@mode MODERN
@since 1.16.12
@description
Displays the identity and token-service operations supported by the installed AWS CLI.
@run
aws sts help
@end

@command Show AWS Route 53 native help
@mode MODERN
@since 1.16.12
@description
Displays the Route 53 operations and global options supported by the installed AWS CLI.
@run
aws route53 help
@end

@command Show AWS EC2 native help
@mode MODERN
@since 1.16.12
@description
Displays the EC2 operations and global options supported by the installed AWS CLI.
@run
aws ec2 help
@end

@command Show AWS Systems Manager native help
@mode MODERN
@since 1.16.12
@description
Displays the Systems Manager operations, including session commands, supported by the installed AWS CLI.
@run
aws ssm help
@end
