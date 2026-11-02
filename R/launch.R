#' Launch the IMF dataset explorer
#'
#' Browse versioned datasets, select conditional dimension values, review a
#' reproducible query and explicitly retrieve and export observations. Metadata
#' caches and query state are isolated to each Shiny session. Loading the package
#' does not start Shiny or access the network.
#'
#' @param agency_id IMF maintainer ID. Defaults to `"IMF.STA"`.
#' @param launch.browser Whether Shiny should open the application in a browser.
#' @return The result of [shiny::runApp()], invisibly after the application exits.
#' @details Requires imf.data 0.2.0 or later. The initial catalogue is fetched
#'   when a browser session connects; dimensions and code lists are loaded only
#'   after choosing a dataset. Observation requests require a button click.
#' @export
#' @examples
#' if (interactive()) imfexplorer()
imfexplorer <- function(agency_id = "IMF.STA", launch.browser = interactive()) {
  if (!scalar_text(agency_id)) stop("agency_id must be a nonempty string.")
  if (!is.logical(launch.browser) || length(launch.browser) != 1L || is.na(launch.browser)) {
    stop("launch.browser must be TRUE or FALSE.")
  }
  invisible(shiny::runApp(explorer_app(agency_id), launch.browser = launch.browser))
}

explorer_app <- function(agency_id = "IMF.STA", api = imf_adapter()) {
  shiny::shinyApp(explorer_ui(agency_id), explorer_server(agency_id, api))
}
