# imfexplorer

[![Version: 0.2.4](man/figures/badge-version.svg)](DESCRIPTION)
[![R: 4.1 or later](man/figures/badge-r.svg)](https://www.r-project.org/)
[![imf.data: 0.2.0 or later](man/figures/badge-imf-data.svg)](https://pedrobtz.github.io/imf.data/)
[![License: GPL-3](man/figures/badge-license.svg)](https://www.gnu.org/licenses/gpl-3.0.html)

Explore IMF datasets visually, choose dimension values, and download data through a Shiny app powered by [imf.data](https://pedrobtz.github.io/imf.data/).

## Install and open

Requires **R 4.1 or later** and **imf.data 0.2.0 or later**. CRAN and GitHub installation install required dependencies automatically.

### CRAN release

Once the package is accepted and available on CRAN, install the released version with:

```r
install.packages("imfexplorer")
```

Until then, use the GitHub installation below.

### GitHub development version

```r
install.packages("remotes") # Only needed once
remotes::install_github("karamelikli/imfexplorer")
```

### Local source archive

If you have a package source archive and its required dependencies are already installed, use:

```r
install.packages("imfexplorer_0.2.4.tar.gz", repos = NULL, type = "source")
```

For a local source checkout with automatic dependency installation, use `remotes::install_local("/path/to/imfexplorer")`.

### Launch

The exported launcher has this signature; the argument order preserves existing positional calls:

```r
imfexplorer(
  agency_id = "IMF.STA",
  launch.browser = interactive(),
  background = FALSE
)
```

| Argument | Accepted values | Default | Effect |
| --- | --- | --- | --- |
| `agency_id` | One non-missing, nonempty character string containing a supported IMF SDMX maintainer ID; `"*"` selects all maintainers. | `"IMF.STA"` | Selects the publishing agency whose dataset catalogue is loaded. `"IMF.STA"` identifies the IMF Statistics Department. This selects a catalogue, not a country or region within a dataset. |
| `launch.browser` | One non-missing logical value: `TRUE` or `FALSE`. | `interactive()` | `TRUE` opens the app in a browser; `FALSE` leaves it running without opening a browser. The default is `TRUE` in an interactive R session, including the RStudio console, and `FALSE` in a non-interactive script. This controls browser opening, not whether the console is blocked. |
| `background` | One non-missing logical value: `TRUE` or `FALSE`. | `FALSE` | `FALSE` runs Shiny in the current R process and occupies the console until the app stops. `TRUE` starts a separate supervised process, waits for the local server to be ready, then returns a handle so you can continue using the same console. Background mode requires an installed package and the optional `callr` dependency. |

For the default blocking launch after installation:

```r
imfexplorer::imfexplorer()
```

To launch without automatically opening a browser:

```r
imfexplorer::imfexplorer(launch.browser = FALSE)
```

For a blocking launch, copy the URL in Shiny's `Listening on ...` console message into your browser. The console remains occupied until you stop the app, for example with Ctrl+C in a terminal or the Stop button in RStudio. The launcher returns the result of `shiny::runApp()` invisibly after the app exits.

To find other supported maintainer IDs, inspect the `agency` column of the IMF catalogue and pass an ID from it as `agency_id`:

```r
catalogue <- imf.data::list_datasets("*")
sort(unique(catalogue$agency))
other_ids <- setdiff(unique(catalogue$agency), "IMF.STA")
if (length(other_ids) > 0L) {
  imfexplorer::imfexplorer(agency_id = other_ids[[1]])
}
```

To keep using the same R console, including in RStudio, opt into background mode:

```r
install.packages("callr") # Only needed once for background mode
app <- imfexplorer::imfexplorer(background = TRUE, launch.browser = TRUE)
print(1 + 1) # Run another command while the app is open
app$url # Local URL of the running app
app$is_alive() # TRUE while the server is running
app$stop() # Stop the background server when finished
app$is_alive() # FALSE
```

Background mode returns an `imfexplorer_process` handle invisibly once the server is ready. Use `app$url` to access the app manually if you set `launch.browser = FALSE`; when `TRUE`, the parent session opens the browser only after readiness. The handle also exposes the underlying `callr` process as `app$process`. Calling `app$stop()` again is safe.

Keep `app` while using the server: its process may be cleaned up when the handle is garbage-collected. The supervised child stops when the parent R session exits or restarts. Closing a browser tab alone does not stop it. The child uses the parent's R library paths, including custom libraries.

Startup is checked for at most 30 seconds, plus a bounded local HTTP probe. A failed launch stops the child and reports diagnostics and log paths. Logs are retained in the parent session's temporary directory; inspect them with `readLines(app$logs$stderr)` or `readLines(app$logs$stdout)`. The optional `callr` package is needed only for background mode; default blocking launches do not require it.

## A quick tour

### 1. Find a dataset

Search dataset IDs, names or descriptions using the full-width search box. All three fields are selected by default; use the **Search in** checkboxes to narrow your search. Select a row to explore its dimensions.

![Dataset browser showing a search for CPI](man/figures/README-datasets.png)

### 2. Choose values and time options

Search and select codes in each dimension card. Use **Select all available**, remove individual items with **x**, or **Clear** a selection. An empty dimension means unrestricted.

**Update available values** helps you browse codes matching your other selections. Availability is also checked automatically when you retrieve data. Unavailable selected codes stay visible so you can correct them.

Choose **All periods**, a **Period range**, or **Latest N per series**, then review the generated query.

![CPI dimension cards with USA, headline CPI and monthly frequency selected](man/figures/README-dimensions.png)

### 3. Retrieve and export

Optionally enable **Exclude unavailable or unverified selections before retrieval** to remove flagged codes and recheck the remaining query. Excluded codes are listed with the retrieval status. If a dimension has no verified selected codes left, select an available value or explicitly clear it before continuing. Dimension-availability request failures still require a successful retry.

Click **Retrieve data** to download observations. Browse the table, view a time-series plot when supported, and download **Excel** or **RDS** below the table.

![Retrieved monthly CPI observations, download controls and time-series plot](man/figures/README-results.png)

*Screenshots captured on 4 November 2026 using live IMF CPI data: USA, monthly frequency, latest 12 observations. Available datasets, versions and observations can change.*

## Save and reuse a query

- **R script:** download runnable code from the Review tab.
- **Query JSON:** save your selections and restore them later with **Restore query JSON** in the sidebar.
- **Excel:** export observations to the **Data** sheet, with **Metadata**, **Variables** and **Codes** sheets. Metadata include the exact query, dataset/version, retrieval time and code labels. The **Variables** sheet describes each column, and **Codes** defines values such as `G001: World` and `NSA: Not seasonally adjusted (NSA)` using IMF's original labels.
- **RDS:** export the same observations as a data frame with metadata attached. Read them in R with:

```r
data <- readRDS("imf-data.rds")
metadata <- attr(data, "imf_metadata")
metadata$query
metadata$dataset
attr(data[["COUNTRY"]], "label") # Variable label, when COUNTRY is present
attr(data[["COUNTRY"]], "description") # Variable description
attr(data[["COUNTRY"]], "code_labels") # Named vector: code -> label
```

Each RDS column carries a `label` and `description`. Coded columns also carry named `code_labels` and `code_descriptions` vectors. Original values and column types are preserved. Missing descriptions remain explicit; labels are taken from available values and the dataset's concepts and codelists.

Metadata are captured with the result. If additional variable definitions cannot be loaded, exports retain the available descriptions and labels, together with the failure message.

Selections remain editable. If you change a query after retrieval, existing results are marked **EARLIER QUERY** until you retrieve again. **Clear current query** starts a new selection.

## Useful tips

- Empty dimensions and unrestricted time ranges can produce large requests; acknowledge the warning before retrieving.
- **Latest N** applies to each series, not the total number of returned rows.
- If a plot is unsuitable, the data table and downloads remain available.
- After updating the package, stop the old app and restart R before launching again.

For source installation, use the GitHub or local archive methods described above.

## License

GPL-3.
