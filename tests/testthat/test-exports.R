test_that("Excel and RDS exports preserve observations and the metadata snapshot", {
  testthat::skip_if_not_installed("readxl")
  f <- fixture_api()
  q <- new_query("TEST", "A", "1", list(REGION = "X", METRIC = "index"), last_n_obs = 2)
  data <- f$api$data(q)
  dims <- f$api$dimensions(q)
  values <- stats::setNames(
    lapply(c("REGION", "METRIC"), function(dim) f$api$values(q, dim)),
    c("REGION", "METRIC")
  )
  structure <- list(data = list(dataflows = list(list(id = "A", description = "Synthetic metadata"))))
  data <- annotate_result(data, result_metadata(data, q, f$api$datasets("TEST")[1, ], dims, values,
    structure = structure, excluded = "REGION: missing"
  ))
  meta <- attr(data, "imf_metadata")
  expect_identical(meta$dimension_values$REGION$code, "X")
  expect_identical(meta$dimension_values$REGION$name, "Label X")
  expect_identical(meta$structure, structure)
  expect_match(meta$retrieved_at_utc, "Z$")
  rds <- tempfile(fileext = ".rds")
  xlsx <- tempfile(fileext = ".xlsx")
  on.exit(unlink(c(rds, xlsx)))
  saveRDS(data, rds)
  restored <- readRDS(rds)
  expect_identical(restored, data)
  expect_s3_class(restored, "data.frame")
  write_result_excel(data, xlsx)
  expect_identical(
    readxl::excel_sheets(xlsx),
    c("Data", "Metadata", "Variables", "Codes")
  )
  observations <- readxl::read_xlsx(xlsx, sheet = "Data")
  expect_identical(observations$OBS_VALUE, as.vector(data$OBS_VALUE))
  expect_identical(observations$TIME_PERIOD, as.vector(data$TIME_PERIOD))
  metadata <- readxl::read_xlsx(xlsx, sheet = "Metadata")
  expect_identical(metadata$value[metadata$path == "query/version"], "1")
  expect_identical(metadata$value[metadata$path == "excluded_selections"], "REGION: missing")
  codes <- readxl::read_xlsx(xlsx, sheet = "Codes")
  expect_identical(codes$name[codes$variable == "REGION"], "Label X")
  expect_identical(readxl::read_xlsx(xlsx, sheet = "Variables")$variable, names(data))
  expect_identical(attr(restored$REGION, "code_labels"), c(X = "Label X"))
  expect_identical(attr(restored$REGION, "description"), "REGION")
  expect_identical(attr(data, "imf_metadata"), meta)
  attr(data, "imf_metadata") <- NULL
  expect_error(write_result_excel(data, xlsx), "no metadata snapshot")
})

test_that("metadata failures do not discard observations and unsuccessful requests can retry", {
  f <- fixture_api()
  calls <- 0L
  f$api$structure <- function(q) {
    calls <<- calls + 1L
    if (calls == 1L) stop("synthetic structure failure")
    list(id = q$dataset, version = q$version)
  }
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    do.call(session$setInputs, stats::setNames(list("X", "index"), c(control_id(1), control_id(2))))
    expect_equal(calls, 0L)
    session$setInputs(retrieve = 1L, broad_ok = TRUE)
    expect_null(rv$result_error)
    expect_equal(nrow(rv$results), 2)
    meta <- attr(rv$results, "imf_metadata")
    expect_identical(meta$structure_status, "unavailable")
    expect_match(meta$structure_error, "synthetic structure failure")
    session$setInputs(retrieve = 2L, broad_ok = TRUE)
    meta <- attr(rv$results, "imf_metadata")
    expect_identical(meta$structure, list(id = "A", version = "1"))
    expect_identical(meta$structure_status, "available")
    # Later selection changes leave the prior result and its metadata together.
    do.call(session$setInputs, stats::setNames(list("limited"), control_id(2)))
    expect_identical(attr(rv$results, "imf_metadata"), meta)
    expect_identical(meta$query$filters$METRIC, "index")
    expect_match(output$result_status$html, "EARLIER QUERY")
    session$setInputs(retrieve = 3L, broad_ok = TRUE)
    expect_equal(calls, 2L)
    expect_identical(attr(rv$results, "imf_metadata")$query$filters$METRIC, "limited")
    f$log$fail_data <- TRUE
    session$setInputs(retrieve = 4L, broad_ok = TRUE)
    expect_identical(attr(rv$results, "imf_metadata")$query$filters$METRIC, "limited")
    expect_match(rv$result_error, "fixture data failure")
    expect_equal(calls, 2L)
  })
})

test_that("full metadata requests use the exact dataset identity and references", {
  seen <- NULL
  testthat::local_mocked_bindings(sdmx_structure = function(...) {
    seen <<- list(...)
    list(data = "metadata")
  }, .package = "imf.data")
  expect_identical(imf_adapter()$structure(new_query("TEST", "A", "1")), list(data = "metadata"))
  expect_identical(seen, list(
    structure_type = "dataflow", agency_id = "TEST", resource_id = "A", version = "1", references = "all"
  ))
})

test_that("long metadata strings are lossless and observation limits are explicit", {
  text <- paste(rep("metadata", 5000), collapse = "")
  table <- metadata_table(list(description = text, missing = NA_character_, absent = NULL))
  chunks <- table[table$path == "description", ]
  expect_identical(paste0(chunks$value, collapse = ""), text)
  expect_true(all(nchar(chunks$value) <= 15000))
  expect_true(is.na(table$value[table$path == "missing"]))
  expect_identical(table$value[table$path == "absent"], "(none)")
  f <- fixture_api()
  q <- new_query("TEST", "A", "1")
  data <- f$api$data(q)[FALSE, ]
  attr(data, "imf_metadata") <- result_metadata(
    data, q, f$api$datasets("TEST")[1, ], f$api$dimensions(q),
    list(REGION = normalize_values(data.frame(code = "X", name = "Known region")))
  )
  file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(file))
  expect_no_error(write_result_excel(data, file))
  data <- f$api$data(q)
  data$long <- text
  attr(data, "imf_metadata") <- result_metadata(data, q, f$api$datasets("TEST")[1, ], f$api$dimensions(q), list())
  expect_error(write_result_excel(data, file), "Excel cell text limit.*RDS")
})
