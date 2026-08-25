@title AWS commands

@description
Curated AWS CLI knowledge for identity checks and read-only Route 53 inventory. Commands are
displayed as inert text and are never executed by BASH_GOD.


@group identity

@command Show the current AWS identity
@mode MODERN
@description
Displays the account, principal ARN, and user ID used by subsequent AWS CLI commands.
@run
aws sts get-caller-identity
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
