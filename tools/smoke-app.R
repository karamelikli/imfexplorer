# Local browser smoke harness. Uses explicitly SYNTHETIC fixtures, never IMF results.
pkgload::load_all(".", quiet = TRUE)
source("tests/testthat/helper-fixtures.R")
api <- fixture_api()$api
api$metadata_catalogue <- function() {
  normalize_datasets(data.frame(agency = "TEST", id = "A_REPORT", version = "9", name = "Synthetic methodology"))
}
api$metadata <- function(report) {
  list(data = list(metadataSets = list(list(
    id = report$id[[1]], version = report$version[[1]], description = "SYNTHETIC metadata report"
  ))))
}
# Optional larger synthetic result for checking table/export layout.
rows <- as.integer(Sys.getenv("IMFEXPLORER_SMOKE_ROWS", "2"))
if (!is.na(rows) && rows > 2L) {
  original_data <- api$data
  api$data <- function(q) {
    data <- original_data(q)
    data <- data[rep(seq_len(nrow(data)), length.out = rows), , drop = FALSE]
    data$TIME_PERIOD <- as.character(1900L + seq_len(rows))
    rownames(data) <- NULL
    data
  }
}
shiny::runApp(explorer_app("TEST", api),
  host = "127.0.0.1", port = 7854,
  launch.browser = FALSE
)
