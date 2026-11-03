test_that("report catalogue and full reports use sdmx_metadata with independent identities", {
  seen <- list()
  full <- list(data = list(metadataSets = list(list(id = "REPORT_A", attributes = list(note = "Methodology")))))
  testthat::local_mocked_bindings(sdmx_metadata = function(...) {
    args <- list(...)
    seen[[length(seen) + 1L]] <<- args
    if (identical(args$detail, "allstubs")) {
      return(list(data = list(metadataSets = list(list(
        agencyID = "PROVIDER", id = "REPORT_A", version = "9", name = "Synthetic report"
      )))))
    }
    full
  }, .package = "imf.data")
  api <- imf_adapter()
  reports <- api$metadata_catalogue()
  expect_identical(reports$agency, "PROVIDER")
  expect_identical(reports$id, "REPORT_A")
  expect_identical(api$metadata(reports), full)
  expect_identical(seen[[1]], list(detail = "allstubs"))
  expect_identical(
    seen[[2]],
    list(provider_id = "PROVIDER", metadataset_id = "REPORT_A", version = "9", detail = "full")
  )
})

test_that("automatic reports keep report versions separate and roundtrip to Excel and RDS", {
  f <- fixture_api()
  calls <- 0L
  f$api$metadata_catalogue <- function() {
    normalize_datasets(data.frame(agency = "TEST", id = "A", version = "9", name = "Synthetic report"))
  }
  f$api$metadata <- function(report) {
    calls <<- calls + 1L
    list(data = list(metadataSets = list(list(
      id = report$id[[1]], version = report$version[[1]], attributes = list(methodology = "Synthetic method")
    ))))
  }
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    expect_equal(calls, 0L)
    session$setInputs(retrieve = 1L, broad_ok = TRUE)
    meta <- attr(rv$results, "imf_metadata")
    expect_null(rv$result_error)
    expect_identical(meta$query$version, "1")
    expect_identical(meta$report_status, "available")
    expect_identical(meta$report_request, list(
      provider_id = "TEST", metadataset_id = "A", version = "9", selection = "dataset_id_match"
    ))
    expect_identical(meta$report$data$metadataSets[[1]]$attributes$methodology, "Synthetic method")
    session$setInputs(retrieve = 2L, broad_ok = TRUE)
    expect_equal(calls, 1L)
    rds <- tempfile(fileext = ".rds")
    xlsx <- tempfile(fileext = ".xlsx")
    on.exit(unlink(c(rds, xlsx)))
    saveRDS(rv$results, rds)
    expect_identical(attr(readRDS(rds), "imf_metadata")$report, meta$report)
    write_result_excel(rv$results, xlsx)
    if (requireNamespace("readxl", quietly = TRUE)) {
      report <- readxl::read_xlsx(xlsx, sheet = "Metadata_Report")
      expect_true("Synthetic method" %in% report$value)
    }
  })
})

test_that("missing and ambiguous automatic reports require an explicit choice", {
  f <- fixture_api()
  seen <- NULL
  f$api$metadata_catalogue <- function() {
    rows <- normalize_datasets(data.frame(
      agency = c("P1", "P2"), id = c("REPORT_A", "REPORT_A"), version = c("9", "10")
    ))
    if (isTRUE(f$log$reverse)) rows[2:1, ] else rows
  }
  f$api$metadata <- function(report) {
    seen <<- report
    list(description = "Explicit report")
  }
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    session$setInputs(retrieve = 1L, broad_ok = TRUE)
    expect_null(seen)
    expect_equal(nrow(rv$results), 2)
    meta <- attr(rv$results, "imf_metadata")
    expect_identical(meta$report_status, "unavailable")
    expect_match(meta$report_error, "No unique metadata report")
    expect_null(meta$report_request)
    ambiguous <- retrieve_report(new_query("TEST", "REPORT_A", "1"))
    expect_match(ambiguous$error, "No unique metadata report")
    expect_null(seen)
    session$setInputs(metadata_report = metadata_report_keys(rv$metadata_reports)[2], retrieve = 2L, broad_ok = TRUE)
    meta <- attr(rv$results, "imf_metadata")
    expect_identical(meta$report_request$metadataset_id, "REPORT_A")
    expect_identical(meta$report_request$provider_id, "P2")
    expect_identical(meta$report_request$version, "10")
    expect_identical(meta$report_request$selection, "user_selected")
    expect_identical(seen$agency, "P2")
    # Refreshing/reordering the report catalogue preserves the selected identity.
    f$log$reverse <- TRUE
    rm("metadata_report_catalogue", envir = cache)
    expect_true(load_reports())
    expect_identical(retrieve_report(query())$request$provider_id, "P2")
    session$setInputs(metadata_report = metadata_report_keys(rv$metadata_reports)[1])
    expect_identical(attr(rv$results, "imf_metadata"), meta)
  })
})

test_that("failed report requests retry without blocking observations or losing their identity", {
  f <- fixture_api()
  calls <- 0L
  f$api$metadata_catalogue <- function() {
    normalize_datasets(data.frame(agency = "TEST", id = "A", version = "9"))
  }
  f$api$metadata <- function(report) {
    calls <<- calls + 1L
    if (calls == 1L) stop("Synthetic report failure")
    if (calls == 2L) {
      return(NULL)
    }
    list(description = "Report recovered")
  }
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    session$setInputs(retrieve = 1L, broad_ok = TRUE)
    meta <- attr(rv$results, "imf_metadata")
    expect_null(rv$result_error)
    expect_equal(nrow(rv$results), 2)
    expect_match(meta$report_error, "Synthetic report failure")
    expect_identical(meta$report_request$version, "9")
    session$setInputs(retrieve = 2L, broad_ok = TRUE)
    expect_match(attr(rv$results, "imf_metadata")$report_error, "no content")
    session$setInputs(retrieve = 3L, broad_ok = TRUE)
    expect_identical(attr(rv$results, "imf_metadata")$report_status, "available")
    expect_equal(calls, 3L)
  })
})
