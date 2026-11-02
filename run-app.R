# Run this file to launch the current workspace source, even when an older
# imfexplorer namespace remains loaded in the R session. No global assignments.
local({
  source_files <- vapply(sys.frames(), function(frame) {
    file <- frame$ofile
    if (is.character(file) && length(file) == 1L) file else NA_character_
  }, character(1))
  source_files <- source_files[!is.na(source_files)]
  entry <- if (length(source_files)) tail(source_files, 1L) else {
    file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else "run-app.R"
  }
  root <- dirname(normalizePath(entry, mustWork = TRUE))
  if (!file.exists(file.path(root, "DESCRIPTION")) || !dir.exists(file.path(root, "R")))
    stop("Run the run-app.R file inside the imfexplorer source directory.")
  app_source <- new.env(parent = globalenv())
  for (file in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) {
    sys.source(file, envir = app_source)
  }
  message("Launching current imfexplorer workspace source: ", root)
  app_source$imfexplorer()
})
