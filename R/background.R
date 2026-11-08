#' Probe the local background app without creating a Shiny session
#'
#' Request the root HTTP page only. No WebSocket connection or IMF metadata
#' request is made by this readiness check.
#'
#' @param port Local TCP port to probe.
#' @param timeout Maximum time in seconds for a socket operation.
#' @return TRUE when the server responds with HTTP 200; FALSE otherwise.
#' @keywords internal
background_ready <- function(port, timeout = 1) {
  tryCatch(suppressWarnings({
    connection <- socketConnection("127.0.0.1", port = port, open = "r+", blocking = TRUE, timeout = timeout)
    on.exit(close(connection), add = TRUE)
    writeLines(c("GET / HTTP/1.0", "Host: 127.0.0.1", "Connection: close", "", ""), connection, sep = "\r\n")
    flush(connection)
    status <- readLines(connection, n = 1L, warn = FALSE)
    length(status) == 1L && grepl("^HTTP/[0-9.]+ 200( |$)", status)
  }), error = function(e) FALSE)
}

#' Stop a background app process
#'
#' @param process The child process returned by [callr::r_bg()].
#' @return Invisibly NULL, after terminating and waiting for a running child.
#'   An already stopped child needs no action.
#' @keywords internal
stop_background <- function(process) {
  if (process$is_alive()) {
    process$kill()
    process$wait(timeout = 5000)
  }
  invisible(NULL)
}

#' Describe a failed background launch with retained diagnostics
#'
#' @param reason The startup failure or timeout message.
#' @param logs Named stdout and stderr log paths.
#' @return A character scalar including log paths and recent child output.
#' @keywords internal
background_failure <- function(reason, logs) {
  diagnostics <- vapply(logs, function(path) {
    lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
    paste(utils::tail(lines, 15L), collapse = "\n")
  }, character(1))
  paste0(
    "Background imfexplorer launch failed: ", reason,
    "\nCheck the child diagnostics and installed package dependencies.",
    "\nstdout: ", logs$stdout, "\nstderr: ", logs$stderr,
    if (any(nzchar(diagnostics))) {
      paste0("\nRecent child output:\n", paste(diagnostics[nzchar(diagnostics)], collapse = "\n"))
    }
  )
}

#' Start a supervised installed explorer in a separate R process
#'
#' @inheritParams imfexplorer
#' @param startup_timeout Maximum readiness wait in seconds.
#' @param package_path Installed package directory, normally resolved from the
#'   parent's loaded namespace. Source-only checkouts must be installed first.
#' @return A process handle list documented by [imfexplorer()].
#' @details The child function receives all arguments explicitly, loads this
#'   exact package installation and reuses [explorer_app()]. Its browser callback
#'   writes a readiness marker after Shiny binds the server; the parent then
#'   checks HTTP readiness before opening a browser or returning the handle.
#' @keywords internal
background_explorer <- function(agency_id, launch.browser, startup_timeout = 30,
                                package_path = NULL) {
  if (!requireNamespace("callr", quietly = TRUE)) {
    stop('Background mode requires callr. Install it with install.packages("callr").', call. = FALSE)
  }
  if (is.null(package_path) && isNamespace(environment(background_explorer))) {
    package_path <- getNamespaceInfo(environment(background_explorer), "path")
  }
  if (is.null(package_path) || !file.exists(file.path(package_path, "Meta", "package.rds"))) {
    stop(paste(
      "Background mode requires an installed imfexplorer package.",
      "Install with remotes::install_local() or remotes::install_github('karamelikli/imfexplorer'), then restart R."
    ), call. = FALSE)
  }
  package_path <- normalizePath(package_path, mustWork = TRUE)
  port <- httpuv::randomPort(host = "127.0.0.1")
  directory <- tempfile("imfexplorer-background-")
  dir.create(directory)
  logs <- list(stdout = file.path(directory, "stdout.log"), stderr = file.path(directory, "stderr.log"))
  ready_file <- file.path(directory, "ready")
  token <- basename(directory)
  process <- NULL
  successful <- FALSE
  on.exit(
    {
      if (!successful && !is.null(process)) stop_background(process)
      unlink(ready_file)
    },
    add = TRUE
  )
  process <- tryCatch(callr::r_bg(
    function(agency_id, port, ready_file, token, package_path) {
      namespace <- loadNamespace("imfexplorer", lib.loc = dirname(package_path))
      loaded_path <- normalizePath(getNamespaceInfo(namespace, "path"), mustWork = TRUE)
      if (!identical(loaded_path, package_path)) stop("The child loaded a different imfexplorer installation.")
      app <- get("explorer_app", envir = namespace)(agency_id)
      shiny::runApp(app,
        host = "127.0.0.1", port = port, display.mode = "normal",
        launch.browser = function(url) writeLines(token, ready_file)
      )
    },
    args = list(
      agency_id = agency_id, port = port, ready_file = ready_file,
      token = token, package_path = package_path
    ),
    libpath = unique(c(dirname(package_path), .libPaths())),
    supervise = TRUE, stdout = logs$stdout, stderr = logs$stderr,
    user_profile = FALSE, system_profile = FALSE
  ), error = function(e) stop(background_failure(conditionMessage(e), logs), call. = FALSE))
  deadline <- unname(proc.time()["elapsed"]) + startup_timeout
  repeat {
    if (!process$is_alive()) {
      reason <- tryCatch(
        {
          process$get_result()
          "The child exited before the server became ready."
        },
        error = function(e) conditionMessage(e)
      )
      stop(background_failure(reason, logs), call. = FALSE)
    }
    remaining <- deadline - unname(proc.time()["elapsed"])
    if (remaining <= 0) {
      stop(background_failure(paste("Startup timed out after", startup_timeout, "seconds."), logs), call. = FALSE)
    }
    marker <- if (file.exists(ready_file)) readLines(ready_file, warn = FALSE) else character()
    if (identical(marker, token) && background_ready(port, timeout = 1)) break
    Sys.sleep(min(0.1, remaining))
  }
  handle <- structure(list(
    url = paste0("http://127.0.0.1:", port, "/"), process = process, logs = logs,
    is_alive = function() process$is_alive(), stop = function() stop_background(process)
  ), class = "imfexplorer_process")
  if (launch.browser) utils::browseURL(handle$url)
  successful <- TRUE
  handle
}
