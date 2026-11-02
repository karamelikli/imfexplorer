# imfexplorer 0.2.3

- Organize the source as a standalone imfexplorer package repository and RStudio project.
- Format package, test and development R files with styler and add a project lintr configuration.
- Use an explicit session-local observer registry and simplify validation expressions to meet lint rules.
- Add a read-only formatting/lint check and document the RStudio addin workflow.

# imfexplorer 0.2.2

- Keep CSV/RDS download controls in a separate section below the entire results table and pagination. Use content-based table height so longer pages cannot overlap exports.

# imfexplorer 0.2.1

- Retrieve data automatically validates changed selections, refreshing only stale dimension availability. Manual availability updates remain available for browsing choices.
- Keep invalid codes and API errors visible; retrying retrieval automatically retries failed availability checks.
- Redesign dimension selection with responsive cards, selection badges, clearer statuses, search chips and a Continue to time options action.

# imfexplorer 0.2.0

- Rename the public launcher to `imfexplorer()` (replaces `launch_imf_explorer()`).
- Add a visible Clear current query action that retains the loaded catalogue.
- Add a dedicated dataset search field across IDs, labels, descriptions and versions.
- Show remove buttons on selected dimension items.
- Add Select all available for every dimension, refreshing stale conditional values and retaining flagged selections.
- Adopt GPL-3 and set Huseyin karamelikli as author and maintainer.
