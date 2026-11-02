test_that("the renamed public launcher builds the app without opening a browser", {
  captured <- NULL
  testthat::local_mocked_bindings(runApp = function(appDir, launch.browser) {
    captured <<- list(app = appDir, browser = launch.browser)
    invisible("stopped")
  }, .package = "shiny")
  expect_identical(imfexplorer("TEST", launch.browser = FALSE), "stopped")
  expect_s3_class(captured$app, "shiny.appobj")
  expect_false(captured$browser)
  expect_identical(getNamespaceExports("imfexplorer"), "imfexplorer")
  expect_error(imfexplorer(""), "agency_id")
})

test_that("select all uses all available codes and preserves flagged selections", {
  f <- fixture_api(); messages <- list()
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
      choices = NULL, selected = NULL, server = FALSE, ...) {
    messages[[inputId]] <<- list(choices = choices, selected = selected, server = server)
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact(); session$setInputs(datasets_rows_selected = 1L)
    id <- control_id(1)
    do.call(session$setInputs, stats::setNames(list(1L), paste0(id, "_all")))
    expect_setequal(messages[[id]]$selected, c("X", "Y"))
    expect_true(messages[[id]]$server)
    do.call(session$setInputs, stats::setNames(list("Y", "limited"), c(id, control_id(2))))
    count <- length(f$log$calls)
    do.call(session$setInputs, stats::setNames(list(2L), paste0(id, "_all")))
    expect_equal(length(f$log$calls), count + 1L)
    expect_setequal(messages[[id]]$selected, c("X", "Y"))
    expect_identical(rv$values$REGION$code, "X")
    expect_match(names(messages[[id]]$choices)[2], "unavailable")
    # Existing valid availability is reused without another API call.
    count <- length(f$log$calls)
    do.call(session$setInputs, stats::setNames(list(3L), paste0(id, "_all")))
    expect_equal(length(f$log$calls), count)
    # Simulate removal of a single chip: the remaining code stays selected.
    do.call(session$setInputs, stats::setNames(list("X"), id))
    expect_identical(query()$filters$REGION, "X")
  })
})

test_that("select all distinguishes empty availability from API failures", {
  f <- fixture_api(); messages <- list()
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
      choices = NULL, selected = NULL, ...) {
    messages[[inputId]] <<- selected
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact(); session$setInputs(datasets_rows_selected = 1L)
    id <- control_id(1)
    do.call(session$setInputs, stats::setNames(list("Y", "empty"), c(id, control_id(2))))
    do.call(session$setInputs, stats::setNames(list(1L), paste0(id, "_all")))
    expect_identical(messages[[id]], "Y")
    expect_equal(nrow(rv$values$REGION), 0)
    expect_null(rv$value_errors$REGION)
    f$log$fail_values <- TRUE
    do.call(session$setInputs, stats::setNames(list("index"), control_id(2)))
    rm(list = ls(cache, all.names = TRUE), envir = cache)
    do.call(session$setInputs, stats::setNames(list(2L), paste0(id, "_all")))
    expect_match(rv$value_errors$REGION, "fixture network failure")
    expect_identical(query()$filters$REGION, "Y")
    expect_identical(messages[[id]], "Y")
  })
})

test_that("select all includes code lists larger than selectize's display limit", {
  f <- fixture_api(); messages <- list()
  f$api$values <- function(q, dimension) normalize_values(data.frame(code = paste0("C", seq_len(350))))
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
      choices = NULL, selected = NULL, ...) {
    messages[[inputId]] <<- selected
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact(); session$setInputs(datasets_rows_selected = 1L)
    id <- control_id(1)
    do.call(session$setInputs, stats::setNames(list(1L), paste0(id, "_all")))
    expect_length(messages[[id]], 350)
    expect_setequal(messages[[id]], paste0("C", seq_len(350)))
  })
})

test_that("dataset search does not request metadata and clear query retains the catalogue", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(dataset_search = "sectors")
    expect_length(f$log$calls, 1L)
    session$setInputs(datasets_rows_selected = 2L)
    expect_identical(rv$dataset$id, "B")
    catalog <- rv$catalog; count <- length(f$log$calls)
    session$setInputs(clear_query = 1L)
    expect_null(rv$dataset); expect_null(rv$dimensions); expect_null(rv$results)
    expect_null(rv$result_query)
    expect_identical(rv$seed, list())
    expect_identical(rv$catalog, catalog)
    expect_equal(length(f$log$calls), count)
  })
})

test_that("UI exposes dataset search and query clearing", {
  html <- as.character(explorer_ui("TEST"))
  expect_match(html, 'id="dataset_search"')
  expect_match(html, 'id="clear_query"')
})

test_that("large explicit selections still trigger the broad-request warning", {
  q <- new_query("TEST", "A", "1", list(REGION = "X", METRIC = "index"), last_n_obs = 2)
  dims <- fixture_api()$api$dimensions(q)
  expect_false(broad_query(q, dims))
  q$filters$REGION <- paste0("R", 1:100)
  expect_true(broad_query(q, dims))
  q$filters <- list(REGION = paste0("R", 1:40), METRIC = paste0("M", 1:40))
  expect_true(broad_query(q, dims))
})
