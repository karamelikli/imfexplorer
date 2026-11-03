# Development guide

Open `imfexplorer.Rproj` to work on the package. User installation and the visual workflow are described in [README.md](README.md).

## Install a source checkout

From the package directory, install the checkout and its required dependencies:

```r
remotes::install_local(".")
```

## Running the current workspace source

If an already running app still shows an old message after you update the package, stop that app first. Restart R to clear its loaded namespace, then launch the installed package again. Installing new files does not replace a running app's functions.

To run this workspace's source directly, independently of any older loaded package, use:

```r
source("run-app.R")
```

Run this from the package source directory, or supply the full path to its `run-app.R` file. The script loads functions into a private environment and does not assign them into `.GlobalEnv`. From a terminal, `Rscript run-app.R` also works.

## Package structure

```text
imfexplorer/
├── DESCRIPTION
├── NAMESPACE
├── R/                          # API adapters, query logic, UI and server
├── inst/
│   └── app/
│       ├── app.R               # Bundled Shiny entry point
│       └── www/
│           └── imfexplorer.css  # Application stylesheet
├── man/                        # Generated roxygen2 help
├── tests/testthat/             # Offline and optional live tests
├── tools/                      # Development checks and browser harnesses
├── run-app.R                   # Workspace source launcher
└── imfexplorer.Rproj
```

R installs the contents of `inst/` into the package directory. Application resources are resolved with `system.file()` when installed (and with the source directory when using `run-app.R`). Runtime CSS is kept out of R strings. Development scripts and IDE settings remain excluded from the built package.

The public launcher remains `imfexplorer::imfexplorer()`. The bundled app can also be started with default options after installation:

```r
shiny::runApp(system.file("app", package = "imfexplorer", mustWork = TRUE))
```

## Architecture and dependencies

- `R/adapter.R`: the only upstream calls, schema normalization, success-only metadata cache, canonical filter keys, availability status.
- `R/query.R`: query model, validation, safe R serialization and JSON round trips.
- `R/app-ui.R`, `R/app-server.R`, `R/launch.R`: staged interface, session lifecycle, public entry point.
- `R/results.R`: reliable series counts and conservative per-series plots.
- `R/styles.R`: installed/source resource lookup and stylesheet inclusion.
- `inst/app/`: bundled Shiny entry point and static assets.

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

The checked-in `.lintr` keeps the default linters, uses a 120-character line limit (excluding multiline string bodies), and allows the exact Shiny API argument names `launch.browser`, `appDir`, and `inputId` alongside snake_case. Runtime code and test files remain linted. No entire files or lint categories are disabled.

For a read-only formatting and lint check, run `Rscript tools/check-style.R`. RStudio settings use two-space indentation and UTF-8. Formatting/lint packages are development dependencies only; they are not needed to launch the app.

Keep changes on a feature branch. Build archives, `.Rcheck` output, R session files, and IDE state are excluded from Git.


```sh
R CMD build .
R CMD check --no-manual imfexplorer_0.2.3.tar.gz
# Optional network-dependent integration tests:
IMFEXPLORER_LIVE_TESTS=true Rscript -e 'testthat::test_local(filter="live")'
# Local synthetic browser smoke harness (not IMF results):
Rscript tools/smoke-app.R
```

Offline tests use clearly marked synthetic fixtures; ordinary tests never contact IMF. The optional live test uses a narrow CPI query and is skipped unless explicitly enabled.

License: GPL-3. See `COPYING` for the full licence.

## README screenshots

Store application screenshots in `man/figures/` and link them using relative paths from the README. Use a narrow live query, such as monthly CPI for USA with `last_n_obs = 12`. State the capture date and dataset in the caption. If synthetic fixtures are used for a screenshot, label them explicitly; never present them as live IMF results.

To regenerate the three README images, start the live app with this command from the package directory:

```sh
Rscript -e 'pkgload::load_all("."); shiny::runApp(explorer_app(), host="127.0.0.1", port=7854, launch.browser=FALSE)'
```

Start Chrome with remote debugging on port 9225, then run `node tools/capture-readme.cjs` (Node.js and the `ws` module are required). The capture script waits for imported selections to finish loading, uses live responses, and writes only screenshots plus a temporary query JSON file. Update the capture date in the README when regenerating images.
