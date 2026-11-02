# imfexplorer

An installable R package for visually discovering IMF datasets and building reproducible `imf.data` queries. No network requests or application launch occur when the package is loaded.

## Install and launch

Requires R >= 4.1 and **imf.data >= 0.2.0**. The adapter was inspected and verified against installed 0.2.0 and the [official documentation](https://pedrobtz.github.io/imf.data/). Earlier versions use a different API and are unsupported.

Install the package from GitHub using `remotes` (required package dependencies are installed automatically):

```r
install.packages("remotes") # Run once if remotes is not installed
remotes::install_github("karamelikli/imfexplorer")
imfexplorer::imfexplorer()
# Or another agency; keep browser launching under your control:
imfexplorer::imfexplorer(agency_id = "IMF.STA", launch.browser = FALSE)
```

Alternatively, install a local checkout with `install.packages("/path/to/imfexplorer", repos = NULL, type = "source")`, or install the supplied source archive with `R CMD INSTALL imfexplorer_0.2.3.tar.gz`. A normal R installation uses its configured package library; a restricted environment can pass `--library=/path/to/writable/library`.

## Running the current workspace source

If an already running app still shows an old message after you update the package, stop that app first. Restart R to clear its loaded namespace, then launch the installed package again. Installing new files does not replace a running app's functions.

To run this workspace's source directly, independently of any older loaded package, use:

```r
source("run-app.R")
```

Run this from the package source directory, or supply the full path to its `run-app.R` file. The script loads functions into a private environment and does not assign them into `.GlobalEnv`. From a terminal, `Rscript run-app.R` also works.

## Workflow

1. **Dataset:** the session loads only the agency's catalogue. Use **Search datasets** to search across IDs, names, descriptions and versions; select one row. Dimensions and values load for that version only. Enter another agency and click **Load / refresh catalogue** to switch catalogues.
2. **Dimensions:** each non-time dimension has a responsive card with a searchable multiselect, readable name, exact ID, selection count and availability status. Remove an individual selected item with its **x** button. **Select all available** explicitly selects every currently available code, including codes beyond the first 200 search matches, and retains any previously flagged selections. Stale availability is refreshed for that dimension using the current other-dimension filters before selecting all. An empty selection means unrestricted. Select in any order. Use **Update available values** when you want to browse codes matching the current other-dimension filters; retrieval checks stale availability automatically. Each value request uses all other current dimension filters and excludes its own. Selected codes remain in the control even when unavailable, with a visible warning. Clear those codes or adjust other filters and update again. **Retrieve data** automatically checks stale code lists before downloading observations; it blocks only invalid/unavailable selections, empty availability, or API failures. Your selections are retained if validation fails. Empty successful responses and API failures have separate messages.
3. **Time:** choose all periods, a range, or latest N observations per series. These modes are mutually exclusive; inactive fields are ignored. Bounds accept years, quarters, calendar months/dates and reporting months (`2024-M01`). This UI deliberately supports a subset of the upstream SDMX period syntax. Optional attributes accept exact dataset-specific IDs; none are assumed to exist. Unknown IDs produce an upstream error, which can be corrected and retried.
4. **Review:** the visible sidebar summarizes exact identities, version, codes and readable labels. Copy the runnable R code, or download an R script or query JSON. Restore JSON using the sidebar uploader. Import checks schema, identity, exact catalogue version, dimensions and conditional codes. Unavailable identity/dimensions reject import; unavailable codes are retained, flagged and block retrieval until resolved.
5. **Retrieve & export:** data are fetched only on **Retrieve data**. Unrestricted dimensions, an unbounded start, or many explicitly selected codes trigger a broad-request acknowledgement. The large-selection warning uses a conservative risk heuristic (100 codes in a dimension or more than 1,000 candidate combinations), not a count of available series. Latest N is per series and does not bound the number of series. Selection combinations are never presented as an exact series count. Search/page through observations; export CSV or RDS. Query changes visibly mark existing results as belonging to an earlier query. The result details show the exact query used; CSV/RDS always export that displayed result, while script/JSON describe the current query.

**Clear current query** in the sidebar (also **Reset** in the Dataset tab) clears the dataset, dimension selections, time options, attributes, results and dataset search while retaining the loaded agency catalogue and metadata cache. Dataset changes also clear dependent selections, time options and results. **Clear metadata cache / refresh selected dataset** clears the session cache, checks whether the exact version still exists and reloads dimensions/values, retaining filters where possible. There is no automatic retry loop. All application state and caches are private to a Shiny session. There are no assignments to `.GlobalEnv`.

## Reproducible queries

The review code uses explicit `imf.data::get_data()` and a named `filters` list, with agency, version and supported time arguments. It is generated using R language objects and `deparse()`; imported text is never evaluated.

```r
filters <- list(
  COUNTRY = "USA", INDEX_TYPE = "CPI", COICOP_1999 = "_T",
  TYPE_OF_TRANSFORMATION = "IX", FREQUENCY = "M"
)
data <- imf.data::get_data(
  dataflow = "CPI", filters = filters, agency_id = "IMF.STA",
  version = "5.0.0", last_n_obs = 2
)
```

This is a real query shape verified during development; catalogue versions and availability can change. Use the GUI to inspect current metadata. Saved JSON uses schema version 1, preserves code arrays, and pins the exact dataset version. Code labels are reloaded from metadata rather than embedded in the configuration. A single-code array is retained as an array; the importer also accepts scalar strings for convenience.

## Plots and counts

Observation count is the number of returned rows. Series count uses distinct combinations of **all** non-time dimensions, and is omitted when those columns are missing. No series estimate is inferred from selected code counts.

The simple base R plot uses separate panels for every complete dimension/unit combination (up to 12), preserving numeric values and returned unit/scale attributes without conversion. No lines cross series or unit groups. Missing unit metadata is explicitly noted; request exact unit attribute IDs when available. Missing dimensions, duplicate periods or unsupported periods disable the plot with an explanation while retaining the full table. Annual, quarterly, monthly (including IMF reporting-month syntax) and daily periods are supported. More complex SDMX calendars remain available in the table.

## Architecture and dependencies

- `R/adapter.R`: the only upstream calls, schema normalization, success-only metadata cache, canonical filter keys, availability status.
- `R/query.R`: query model, validation, safe R serialization and JSON round trips.
- `R/app-ui.R`, `R/app-server.R`, `R/launch.R`: staged interface, session lifecycle, public entry point.
- `R/results.R`: reliable series counts and conservative per-series plots.

Shiny manages the interface, bslib supplies navigation/layout, DT supplies searchable server-side paginated tables, and jsonlite handles saved configurations and unambiguous cache keys. No plotting framework or other major dependency is added. Searchable code lists use server-side selectize with at most 200 matching options shown at once; metadata are fetched in full for only the chosen dataset.

IMF requests are synchronous: loading indicators appear during requests, and a slow request can occupy the R process. For multi-user hosting, run multiple Shiny worker processes. API latency, availability, labels and version retention are outside this package's control.

## Development checks

Open `imfexplorer.Rproj` to make this folder the active RStudio package project. The **Style active package** and **Lint package** addins then target this package. Their command-line equivalents are:

```r
install.packages(c("testthat", "roxygen2", "styler", "lintr", "pkgload"))
styler::style_pkg()
lintr::lint_package()
testthat::test_local()
roxygen2::roxygenise()
```

The checked-in `.lintr` keeps the default linters, uses a 120-character line limit (excluding multiline string bodies such as embedded CSS), and allows the exact Shiny API argument names `launch.browser`, `appDir`, and `inputId` alongside snake_case. Runtime code and test files remain linted. No entire files or lint categories are disabled.

For a read-only formatting and lint check, run `Rscript tools/check-style.R`. RStudio settings use two-space indentation and UTF-8. Formatting/lint packages are development dependencies only; they are not needed to launch the app.

The Git repository root is this package folder, with `origin` pointing at `https://github.com/karamelikli/imfexplorer.git`. Build archives, `.Rcheck` output, R session files, and IDE state are excluded from Git. After authenticating GitHub access, publish committed changes with `git push --set-upstream origin main`.


```sh
R CMD build .
R CMD check --no-manual imfexplorer_0.2.3.tar.gz
# Optional network-dependent integration tests:
IMFEXPLORER_LIVE_TESTS=true Rscript -e 'testthat::test_local(filter="live")'
# Local synthetic browser smoke harness (not IMF results):
Rscript tools/smoke-app.R
```

Offline tests use clearly marked synthetic fixtures; ordinary tests never contact IMF. The optional live test uses a narrow CPI query and is skipped unless explicitly enabled. See `VERIFICATION.md` in the source workspace for actual verification results and limitations.

License: GPL-3. See `COPYING` for the full licence.
