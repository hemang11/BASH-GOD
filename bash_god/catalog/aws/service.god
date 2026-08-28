@title AWS commands

@description
Curated AWS CLI knowledge for identity checks, EC2 instance-profile credentials, Systems Manager
sessions, instance metadata, and read-only Route 53 inventory. Commands are displayed as inert text
and are never executed by BASH_GOD.


@group identity

@command Show the current AWS identity
@mode MODERN
@description
Displays the account, principal ARN, and user ID used by subsequent AWS CLI commands.
@run
aws sts get-caller-identity
@end


@group ec2

@command Show the IAM instance profile attached to an instance
@mode MODERN
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
@description
Starts an interactive Systems Manager session on an EC2 instance without SSH, an open inbound port, or a key pair.
@run
aws ssm start-session --target <instance_id>
@params
--target | <instance_id> | EC2 instance registered as a managed node running the SSM agent
@optional
--region | <aws_region> | Region holding the instance when it differs from the configured default
@end

@command Open a Session Manager shell as a specific host user
@mode MODERN
@description
Starts a Systems Manager session that lands directly in another host account's login shell, avoiding a manual user switch after connecting.
@run
aws ssm start-session --target <instance_id> --document-name AWS-StartInteractiveCommand --parameters command="sudo -u <host_user> -i"
@params
--document-name | AWS-StartInteractiveCommand | Session document that runs one interactive command instead of the default shell
--parameters | command="sudo -u <host_user> -i" | Interactive command opening the target user's login shell
@notes
Enabling Run As support in Session Manager preferences achieves the same landing user for every session without repeating this document.
@end

@command List active Session Manager sessions
@mode MODERN
@description
Lists Systems Manager sessions currently connected in the region, including the target instance and the principal that opened each one.
@run
aws ssm describe-sessions --state Active --output table
@params
--state | Active | Show connected sessions rather than historical ones
@end


@group imds

@command Show the IAM role served by instance metadata
@mode LOCAL
@description
Reports the instance profile ARN and role that the metadata service is serving on an EC2 host, which is where the AWS CLI finds credentials when no environment variables or credentials file exist.
@run
curl -s http://169.254.169.254/latest/meta-data/iam/info
@notes
This unauthenticated IMDSv1 form returns 401 on an instance that enforces IMDSv2; use the token form there.
@end

@command Show the metadata role name through an IMDSv2 token
@mode LOCAL
@description
Requests a metadata session token and lists the role name whose short-lived credentials the metadata service is serving on an instance that enforces IMDSv2.
@run
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60") && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
@params
-X PUT | /latest/api/token | Request the session token that IMDSv2 requires before any metadata read
-H | X-aws-ec2-metadata-token-ttl-seconds: 60 | Token lifetime in seconds
@notes
This returns only the role name. Appending that name to the same path prints live access keys and a session token, so treat any such output as secret and never paste it into a ticket, log, or chat.
@end

@command Ignore exported keys and fall back to the instance role
@mode LOCAL
@description
Clears the AWS credential environment variables in the current shell so the CLI resolves credentials from instance metadata, which confirms whether an attached instance profile actually works.
@run
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
@notes
The credential chain prefers environment variables, then ~/.aws/credentials, then instance metadata, so exported keys silently mask an attached role until they are cleared. Follow this with aws sts get-caller-identity to see which principal now answers.
@end


@group route53

@command List private Route 53 hosted zones
@mode MODERN
@description
Lists private hosted-zone IDs and DNS names visible through the current AWS account identity.
@run
aws route53 list-hosted-zones --query 'HostedZones[?Config.PrivateZone==`true`].[Id,Name]' --output table
@params
--query | private zones | Keep only hosted zones whose PrivateZone flag is true
--output | table | Render zone IDs and names as a table
@end

@command List private hosted zones associated with one VPC
@mode MODERN
@description
Lists private hosted zones associated with a selected VPC, including zones owned by another account when visible.
@run
aws route53 list-hosted-zones-by-vpc --vpc-id <vpc_id> --vpc-region <aws_region> --query 'HostedZoneSummaries[].[HostedZoneId,Name,Owner.OwningAccount]' --output table
@params
--vpc-id | <vpc_id> | VPC whose associated private zones should be listed
--vpc-region | <aws_region> | AWS region containing the VPC
@end

@command List address and canonical-name records in a hosted zone
@mode MODERN
@description
Lists A, AAAA, and CNAME record names, values, and alias targets from one Route 53 hosted zone.
@run
aws route53 list-resource-record-sets --hosted-zone-id <hosted_zone_id> --query "ResourceRecordSets[?Type=='A' || Type=='AAAA' || Type=='CNAME'].[Name,Type,ResourceRecords[0].Value,AliasTarget.DNSName]" --output table
@params
--hosted-zone-id | <hosted_zone_id> | Route 53 hosted-zone identifier
--query | A, AAAA, and CNAME | Keep hostname-bearing record types and their first value or alias target
@notes
Route 53 normally returns fully qualified DNS names with a trailing dot.
@end

@command Find Route 53 records case-insensitively
@mode MODERN
@description
Searches the names, types, values, and alias targets of A, AAAA, and CNAME records without changing Route 53.
@run
aws route53 list-resource-record-sets --hosted-zone-id <hosted_zone_id> --query "ResourceRecordSets[?Type=='A' || Type=='AAAA' || Type=='CNAME'].[Name,Type,ResourceRecords[0].Value,AliasTarget.DNSName]" --output text | grep -i -- '<search_text>'
@params
--hosted-zone-id | <hosted_zone_id> | Route 53 hosted-zone identifier
TEXT | <search_text> | Partial case-insensitive hostname or value to find
@notes
Repeat this read-only command for each relevant private hosted zone.
@end


@group native

@command Show AWS CLI native help
@mode MODERN
@description
Displays the installed AWS CLI's top-level services and global options.
@run
aws help
@end

@command Show AWS STS native help
@mode MODERN
@description
Displays the identity and token-service operations supported by the installed AWS CLI.
@run
aws sts help
@end

@command Show AWS Route 53 native help
@mode MODERN
@description
Displays the Route 53 operations and global options supported by the installed AWS CLI.
@run
aws route53 help
@end

@command Show AWS EC2 native help
@mode MODERN
@description
Displays the EC2 operations and global options supported by the installed AWS CLI.
@run
aws ec2 help
@end

@command Show AWS Systems Manager native help
@mode MODERN
@description
Displays the Systems Manager operations, including session commands, supported by the installed AWS CLI.
@run
aws ssm help
@end
