# Keeping an executable service in sync with a new native release

This is a maintainer runbook, not an automated process. Delivery to users rides the existing
update-check machinery: when a new BASH_GOD release lands with updated catalog data, a bare
interactive `god` offers it the same way it always has. There is no separate
"catalog sync" release channel.

It applies to a discovery-based service whose catalog declares `@discover` — Elasticsearch, Kafka,
Kubernetes, AWS, and MongoDB today. Elasticsearch is the useful exception where the declared curl
probe discovers the client while its catalog-declared version request reads the service's root
endpoint; cache the Elasticsearch version, never curl's version. A service that declares
`@execution PATH` deliberately has no product version axis. A catalog with neither marker stays
display-only and needs no execution bookkeeping.

## When a major (or otherwise breaking) native release lands

1. **Read the native release notes** for removed flags, renamed tools, and changed defaults —
   specifically anything that would make an existing `@run` line wrong or a flag stop working.

2. **Decide per affected record**:
   - **Nothing changed for this record** — retain its existing `@since`. Most records outlive several
     native releases untouched.
   - **A flag or tool was removed** — add `@until <last-good-version>` to the record that no longer
     works, using the last version confirmed to still support it. `@until` is a fact about when a
     record stops working, never a stand-in for `@synced`.
   - **A flag or tool was added and the old form still works** — add a *new* record whose mandatory
     `@since <version>` is the first verified release for the new form; leave the old record as-is
     (or add `@until` to it if the old form is now actively wrong, not just outdated).
   - **Both an old and a new form are valid for some version range** — give both records the same
     `@intent <slug>` (lowercase kebab-case) so search collapses them to one row instead of showing
     near-duplicates. See `bash_god/AGENTS.md`'s Execution Metadata section for the exact mechanics
     and a worked example.

3. **Add the new variant as a normal catalog record** — same `@group`, same field requirements
   (`@mode`, mandatory `@since`, `@description`, one physical `@run` line) as any other record.
   Every executable-catalog row must be a real command. Express raw in-tool work through the native
   client (for example, its `--eval` mode), and replace child-shell-only operations with a useful
   one-command check.

4. **Bump `@synced <version>`** at the top of the catalog to the version you verified this pass
   against. This is the only field this whole runbook exists to keep current. It is a caution line
   for users on a newer version, never a filter — do not rely on it to hide anything; use `@until` on
   the specific records that actually broke.

5. **Validate and test**:

   ```bash
   ./bash_god/tests/smoke.sh
   ```

   Then hand-verify the changed records against the version boundary you just added: pick a detected
   version just inside the new range and one just outside it, and confirm the record appears/hides as
   intended. `bash_god/discover.sh`'s cache can be primed directly for this without a real install:

   ```bash
   bash -c '
     . bash_god/core.sh
     _god_discover_cache_set kafka.path /opt/kafka/bin
     _god_discover_cache_set kafka.version 3.9.0
     god kafka q "list topics"
   '
   ```

6. **Ship it as a normal release.** Version metadata is catalog data like any other field; it goes
   out the same way a new command or a corrected note would.

## What you are not doing

- Not writing code. `discover.sh`, `resolve.sh`, and `execute.sh` are generic and version-neutral;
  they read `@discover`/`@execution PATH` and per-record metadata as plain catalog facts. A sync
  pass never adds a service-specific execution branch.
- Not touching `probe`/`root`/`scan` in `@discover` unless the native install layout itself changed
  (a new default directory, a renamed binary) — that is a separate, much rarer edit from a version
  bump.
- Not guessing. A new executable-service record without a verified compatibility floor is not ready
  to merge; the validator rejects it instead of allowing an unmarked command into the picker.
