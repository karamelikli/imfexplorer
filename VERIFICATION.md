# Verification — imfexplorer 0.2.3 — 2026-11-02

- Moved the package source into the standalone `imfexplorer/` directory. Package files, development tools, tests, documentation, licence and Git metadata are together; historical source archives and `.Rcheck` output remain outside the repository. A parent workspace compatibility launcher still resolves the moved source.
- Added `imfexplorer.Rproj` with package build settings, UTF-8 and two-space indentation. Open this project before running the RStudio Style active package and Lint package addins.
- Applied installed styler 1.11.0 to all package/test R files and the development launch/check scripts. A subsequent dry-fail check reports no formatting changes.
- Added `.lintr` for lintr 3.4.0: default linters, a 120-character limit excluding multiline string bodies, and explicitly allowed Shiny argument names `launch.browser`, `appDir` and `inputId` alongside snake_case and symbols. No entire files or lint categories are disabled.
- `lintr::lint_package()` and `lintr::lint_dir()` both report **zero findings**. `Rscript tools/check-style.R` passes and does not modify source files.
- Removed runtime super-assignment by keeping observer handles in an explicit per-session environment. Existing lifecycle, reset, conditional selection and retrieval tests continue to pass.
- Tests: **179 passing assertions**, zero failures/errors/warnings; 29 offline test cases and one optional live case skipped.
- Both the parent compatibility launcher and the package-local `run-app.R` were tested with a mocked Shiny runner and resolve the new package directory.
- `R CMD build imfexplorer`: passed; archive `imfexplorer_0.2.3.tar.gz` is outside the repository directory.
- `R CMD check --no-manual imfexplorer_0.2.3.tar.gz`: **Status: OK**, zero package errors/warnings/notes. Installed dependencies were used; the sandbox could not refresh the CRAN index. PDF manual generation was not requested.
- The writable temporary Sass cache was used for checks. Live observation downloads were not repeated for formatting/project organization changes.
- Initialized the package folder as a Git repository, retaining the prior local source history, with `origin` set to `https://github.com/karamelikli/imfexplorer.git`. HTTPS access currently requires authentication; no GitHub token, configured saved credentials, connected GitHub integration or SSH-agent identity is available.

---

# Verification — imfexplorer 0.2.2 — 2026-11-02

- Put CSV/RDS downloads in a dedicated section below the complete retrieved table and pagination, with spacing and wrapping actions.
- Disable DT fill sizing for the results table and use a normal block layout that expands with its contents, preventing overlapping controls.
- Real Chrome layout checks with 120 explicitly synthetic observations passed at 1440px and 390px widths, for page lengths of 10, 25 and 100 rows. Geometry checks confirmed exports start below the complete table wrapper. Browser hit tests confirmed both buttons are unobscured after scrolling.
- `R CMD build .` passed; archive: `imfexplorer_0.2.2.tar.gz`.
- `R CMD check --no-manual imfexplorer_0.2.2.tar.gz`: **Status: OK**, with the existing offline tests passing. The optional live test remains skipped by default. A writable temporary Sass cache was used; the sandbox could not refresh the CRAN index, but dependencies were installed and checked successfully.
- Reproduce the layout test by starting `IMFEXPLORER_SMOKE_ROWS=120 Rscript tools/smoke-app.R` and Chrome on debugging port 9225, then running `node tools/results-layout-smoke.cjs`. Ordinary smoke fixtures still return two synthetic rows.
- Stop any running app before using `source("run-app.R")` to launch the updated workspace source, or install version 0.2.2 and restart R before launching the installed package.
- No live observation requests were made for this layout change. GitHub publishing remains pending authentication.

---

# Verification — imfexplorer 0.2.1 — 2026-11-02

- Retrieve data now automatically refreshes stale dimension availability, then validates the same query snapshot before requesting observations. Invalid codes, empty availability and API failures remain visible and prevent observation downloads; retrying retrieval retries failed metadata checks.
- Fresh availability is reused, including after time-only changes. A sole own-dimension filter now produces the same availability cache key as no filters, avoiding unnecessary requests.
- The selection page uses responsive cards, readable names plus exact IDs, selected-count badges, grouped select-all/clear controls, larger searchable chip inputs, clearer status feedback and a Continue to time options button.
- `testthat::test_local()`: **179 passing assertions**, zero failures/errors/warnings; 29 offline test cases and one optional live case skipped. The test environment uses a writable temporary Sass cache (`R_USER_CACHE_DIR=/tmp/imfexplorer-r-cache`).
- `R CMD build .`: passed; source archive `imfexplorer_0.2.1.tar.gz`.
- Source installation into `/tmp/imfexplorer-library`: passed.
- `R CMD check --no-manual imfexplorer_0.2.1.tar.gz`: **Status: OK**, no package warnings, errors or notes. Dependencies were installed; the sandbox could not refresh the CRAN index. PDF manual generation was not requested.
- Real Chrome browser workflow passed against explicitly synthetic fixtures: edited dimension selections proceeded directly through Review to Retrieve without manual availability refresh; search, select-all, individual removal, invalid-code retention, query clearing, time navigation, plotting, all four downloads and JSON restore passed.
- Selection layout screenshots were inspected at desktop (1440px) and mobile (390px) widths. The mobile page has no horizontal overflow. Preview files are `/tmp/imfexplorer-selection-desktop.png` and `/tmp/imfexplorer-selection-mobile.png`.
- PI report follow-up: the exact legacy warning is absent from both the workspace server and the normally installed 0.2.1 namespace. The installed namespace passed 12 offline assertions for PI 2.0.0 with exactly PRODUCTION_INDEX=IND, TYPE_OF_TRANSFORMATION=IX, all other dimensions unrestricted, and no time bounds. This verifies app dispatch, not a live unrestricted observation download.
- Read-only live `list_dimensions("PI", agency_id="IMF.STA", version="2.0.0")` succeeded and confirmed COUNTRY, PRODUCTION_INDEX, TYPE_OF_TRANSFORMATION, FREQUENCY and TIME_PERIOD.
- Added `run-app.R` to load the workspace functions into a private environment and launch them independently of a previously loaded installed namespace. A mocked launch verified automatic-validation server code; an actual HTTP smoke test returned 200 with the current automatic-validation UI. Stop the old app before using this launcher. The workspace script is excluded from the installable R package.
- Live observation downloads were not repeated for these changes; the actual upstream call arguments remain unchanged. Historical live adapter verification is recorded below. No synthetic data are used by the public launcher.
- GitHub publishing remains pending authentication as recorded below. An updated local Git snapshot is prepared separately.

---

# Verification — imfexplorer 0.2.0 — 2026-11-02

## Changes

- Public launcher renamed to `imfexplorer()`; the former `launch_imf_explorer()` export was removed.
- Dedicated dataset search across ID, name, description, agency and version. Search uses the loaded catalogue, preserving the original row identity when a filtered row is selected.
- Sidebar **Clear current query** clears the selected dataset, dimension filters, time options, attributes, results and dataset search, retaining the agency catalogue and metadata cache. The Dataset tab's Reset action shares that behavior.
- Dimension chips show individual remove buttons. Every dimension has **Select all available** and **Clear selection** actions. Select-all includes all codes, beyond selectize's 200-match display limit, refreshes stale availability with the other current filters, and retains flagged selections.
- Large explicit code selections still require broad-request acknowledgement; candidate combinations are used only as a risk heuristic, never as an exact series count.
- GPL-3 licensing with full text in COPYING. DESCRIPTION includes the requested Huseyin karamelikli author, maintainer email, ORCID and GitHub URLs.

## Verification results

- R 4.6.1, Linux; installed imf.data 0.2.0.
- `testthat::test_local()`: **138 passing assertions**, zero failures/errors/warnings; 22 offline test cases. One optional live test case skips by default.
- New coverage includes renamed launcher/export, select-all with fresh/stale/empty/failed availability, retention of flagged codes, 350-code selections, single-item removal, query clearing without metadata requests, search controls and large-selection warnings.
- `R CMD build .`: passed; delivered archive is `imfexplorer_0.2.0.tar.gz`.
- `R CMD INSTALL --library=/tmp/imfexplorer-library imfexplorer_0.2.0.tar.gz`: passed. Installed author/maintainer/ORCID/licence metadata and the new public export were verified.
- `R CMD check --no-manual imfexplorer_0.2.0.tar.gz`: **Status: OK**, zero package errors/warnings/notes. The sandbox could not refresh the CRAN index; all dependencies were already installed and dependency checks passed. PDF manual generation was not requested.
- Real Chrome browser test, using explicitly synthetic fixtures: dataset text search, correct identity of selected filtered rows, clear-query/search reset, server-side code search, select-all, removal of a single selected chip, conditional availability warnings, retained invalid code, query review, explicit retrieval, plot, stale-result warning, dimension clearing, dataset-change reset, all four downloads, JSON import and clearing restored time options all passed.
- Actual installed public-launcher HTTP smoke test is run separately from the synthetic browser workflow.

The adapter was unchanged in this update. Its installed signatures, documentation and actual returned objects for all four upstream functions were inspected during initial development against imf.data 0.2.0 and https://pedrobtz.github.io/imf.data/. Initial live checks returned 197 IMF.STA datasets, CPI version 5.0.0 metadata, conditional frequency codes, and two observations from a narrow CPI query. All seven optional live assertions passed then; they were not repeated for these UI changes. Synthetic fixtures are never used by the public launcher.

## Publishing

The source archive and a local Git source snapshot are prepared for the requested `https://github.com/karamelikli/imfexplorer` target. Upload is pending authentication: unauthenticated HTTPS Git access required a username, no GitHub environment token or SSH-agent identity was available, and the GitHub integration was not connected. No remote changes were made.

## Remaining limits

Requests remain synchronous. Plots support at most 12 complete series/unit combinations with recognized annual, quarterly, monthly or daily periods. Unavailable/missing unit labels are explicitly noted; original returned values and metadata are preserved. No complete live-service browser workflow was automated; the browser uses labeled synthetic responses and the live adapter was verified separately.
