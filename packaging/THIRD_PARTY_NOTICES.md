# `god-tui` third-party notices

The optional `god-tui` helper is a statically linked Go program. BASH_GOD ships
the following reviewed direct dependencies in that helper. Their source,
copyright notices, and license texts remain available at the linked upstream
release.

| Component | Version | License | Source |
| --- | --- | --- | --- |
| Bubble Tea | v2.0.8 | MIT | <https://github.com/charmbracelet/bubbletea/tree/v2.0.8> |
| `github.com/charmbracelet/x/ansi` | v0.11.7 | MIT | <https://github.com/charmbracelet/x/tree/ansi/v0.11.7/ansi> |

Bubble Tea brings the transitive modules recorded, with their exact checksums,
in BASH_GOD's `go.mod` and `go.sum`. The release builder uses those locked
versions only; it does not fetch or substitute a dependency while assembling an
archive. Go standard-library code is distributed under the Go license.

This notice is packaged beside BASH_GOD's MIT `LICENSE` as
`share/licenses/bash-god/THIRD_PARTY_NOTICES.md`.
