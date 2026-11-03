#' Resolve a bundled application resource
#'
#' Locate files installed from `inst/`, including when the workspace launcher
#' loads the application into its private source environment.
#'
#' @param ... Character path components below `inst/` in a source checkout,
#'   or below the installed package directory.
#' @return An absolute path to an existing resource. Missing resources raise
#'   an error. Installed and pkgload sessions use [system.file()].
#' @keywords internal
explorer_file <- function(...) {
  root <- get0(".imfexplorer_source_root", envir = environment(explorer_file), inherits = FALSE)
  if (!is.null(root)) {
    path <- file.path(root, "inst", ...)
    if (!file.exists(path)) stop("Bundled application resource not found: ", path)
    return(normalizePath(path, mustWork = TRUE))
  }
  system.file(..., package = "imfexplorer", mustWork = TRUE)
}

#' Include the explorer's bundled stylesheet
#'
#' Read the stylesheet distributed in `inst/app/www/` and embed it in the
#' application page. No external stylesheet requests or shared Shiny resource
#' registrations are needed.
#'
#' @return A Shiny HTML `style` tag containing the application's scoped CSS.
#' @seealso [explorer_ui()], [explorer_file()]
#' @keywords internal
explorer_styles <- function() {
  shiny::includeCSS(explorer_file("app", "www", "imfexplorer.css"))
}
