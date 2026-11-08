#' Launch the IMF dataset explorer
#'
#' Browse versioned datasets, select conditional dimension values, review a
#' reproducible query and explicitly retrieve and export observations. Metadata
#' caches and query state are isolated to each Shiny session. Loading the package
#' does not start Shiny or access the network.
#'
#' @param agency_id One non-missing, nonempty character string selecting the
#'   IMF SDMX maintainer (publishing agency) whose dataset catalogue is loaded.
#'   Defaults to `"IMF.STA"`, the IMF Statistics Department. This is not a country
#'   filter. Inspect the `agency` column of `imf.data::list_datasets("*")` for
#'   supported IDs; `"*"` requests all maintainers.
#' @param launch.browser One non-missing logical value. `TRUE` opens a browser;
#'   `FALSE` leaves the server running without opening one. Defaults to
#'   `interactive()`: TRUE in an interactive R or RStudio console and FALSE in a
#'   non-interactive script. For a blocking launch, open the URL printed in
#'   Shiny's `Listening on ...` message manually; in background mode use
#'   `app$url`. This argument controls browser opening, not console blocking.
#' @param background Whether to run the app in a separate R process and return
#'   control to the console once the server is ready. Defaults to `FALSE`.
#'   Requires the optional \pkg{callr} package and an installed copy of
#'   imfexplorer. Works from RStudio and ordinary R consoles.
#' @return Invisibly, the result of [shiny::runApp()] after the blocking app exits,
#'   or, with `background = TRUE`, an `imfexplorer_process` list containing:
#'   \describe{
#'     \item{\code{url}}{The loopback URL to open in a browser.}
#'     \item{\code{is_alive()}}{A function returning whether the child is running.}
#'     \item{\code{stop()}}{A function that stops the child; safe to call again.}
#'     \item{\code{process}}{The underlying \pkg{callr} process handle.}
#'     \item{\code{logs}}{Named paths to the child's stdout and stderr logs.}
#'   }
#' @section Background lifetime and diagnostics:
#' The child is supervised and stops when the parent R session exits, including
#' when restarting R in RStudio. Keep the returned handle while using the app;
#' the process may also be cleaned up when its handle is garbage-collected.
#' Closing a browser tab does not stop the background app. Use `app$stop()`.
#'
#' Startup is checked for at most 30 seconds, plus a bounded local HTTP probe.
#' A failed or timed-out launch stops the child and reports log paths and recent
#' diagnostics. Logs remain in the parent session's temporary directory until
#' that directory is removed. Inspect them with `readLines(app$logs$stderr)`.
#' The child inherits the parent's R library paths, including custom libraries.
#' In background mode the browser is opened by the parent only after readiness;
#' with `launch.browser = FALSE`, use `app$url` manually.
#' @details Requires imf.data 0.2.0 or later. The initial catalogue is fetched
#'   when a browser session connects; dimensions and code lists are loaded only
#'   after choosing a dataset. Observation requests require a button click.
#' @export
#' @examples
#' if (interactive()) imfexplorer()
#' if (interactive() && requireNamespace("callr", quietly = TRUE)) {
#'   app <- imfexplorer(background = TRUE, launch.browser = FALSE)
#'   print(1 + 1) # The same console is immediately available
#'   app$url # Open this URL manually
#'   app$is_alive()
#'   app$stop()
#' }
imfexplorer <- function(agency_id = "IMF.STA", launch.browser = interactive(), background = FALSE) {
  if (!scalar_text(agency_id)) stop("agency_id must be a nonempty string.")
  if (!is.logical(launch.browser) || length(launch.browser) != 1L || is.na(launch.browser)) {
    stop("launch.browser must be TRUE or FALSE.")
  }
  if (!is.logical(background) || length(background) != 1L || is.na(background)) {
    stop("background must be TRUE or FALSE.")
  }
  if (background) {
    return(invisible(background_explorer(agency_id, launch.browser)))
  }
  invisible(shiny::runApp(explorer_app(agency_id), launch.browser = launch.browser))
}

#' Construct an IMF explorer Shiny application
#'
#' Assemble the interface and server without starting an HTTP server or making
#' an IMF request. Requests begin only when the appropriate session events run.
#'
#' @inheritParams imfexplorer
#' @param api An injectable adapter list with the methods described in
#'   [imf_adapter()]. Defaults to the live IMF adapter.
#' @return A `shiny.appobj` created by [shiny::shinyApp()].
#' @seealso [explorer_ui()], [explorer_server()], [imfexplorer()]
#'
#' @keywords internal
explorer_app <- function(agency_id = "IMF.STA", api = imf_adapter()) {
  shiny::shinyApp(explorer_ui(agency_id), explorer_server(agency_id, api))
}
