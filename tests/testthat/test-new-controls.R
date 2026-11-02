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
  f <- fixture_api()
  messages <- list()
  update_choices <- function(session, inputId, choices = NULL, selected = NULL, server = FALSE, ...) {
    messages[[inputId]] <<- list(choices = choices, selected = selected, server = server)
  }
  testthat::local_mocked_bindings(updateSelectizeInput = update_choices, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
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
  f <- fixture_api()
  messages <- list()
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
                                                                  choices = NULL, selected = NULL, ...) {
    messages[[inputId]] <<- selected
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
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
  f <- fixture_api()
  messages <- list()
  f$api$values <- function(q, dimension) normalize_values(data.frame(code = paste0("C", seq_len(350))))
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
                                                                  choices = NULL, selected = NULL, ...) {
    messages[[inputId]] <<- selected
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
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
    catalog <- rv$catalog
    count <- length(f$log$calls)
    session$setInputs(clear_query = 1L)
    expect_null(rv$dataset)
    expect_null(rv$dimensions)
    expect_null(rv$results)
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

test_that("retrieval automatically validates changed selections without manual update", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    do.call(session$setInputs, stats::setNames(list("X", "index"), c(control_id(1), control_id(2))))
    expect_match(query_problem(), "automatically")
    before <- length(f$log$calls)
    session$setInputs(retrieve = 1L)
    new_calls <- f$log$calls[seq.int(before + 1L, length(f$log$calls))]
    expect_identical(vapply(new_calls, `[[`, character(1), "kind"), c("values", "values", "data"))
    expect_equal(nrow(rv$results), 2L)
    expect_identical(rv$result_query$filters, list(METRIC = "index", REGION = "X"))
    expect_null(query_problem())
    # Repeat retrieval with unchanged filters does not re-request metadata.
    before <- length(f$log$calls)
    session$setInputs(retrieve = 2L)
    expect_equal(length(f$log$calls), before + 1L)
    expect_identical(tail(f$log$calls, 1)[[1]]$kind, "data")
    # Time-only edits reuse dimension availability as well.
    session$setInputs(latest = 3L)
    before <- length(f$log$calls)
    session$setInputs(retrieve = 3L)
    expect_equal(length(f$log$calls), before + 1L)
    expect_equal(rv$result_query$last_n_obs, 3)
  })
})

test_that("automatic availability checks retain invalid codes and prevent downloads", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    do.call(session$setInputs, stats::setNames(list("Y", "limited"), c(control_id(1), control_id(2))))
    session$setInputs(retrieve = 1L)
    expect_match(rv$result_error, "Unavailable codes for REGION")
    expect_identical(query()$filters$REGION, "Y")
    expect_null(rv$results)
    expect_false(any(vapply(f$log$calls, function(x) identical(x$kind, "data"), logical(1))))
    # Correct just the invalid selection and retrieve directly again.
    do.call(session$setInputs, stats::setNames(list("X"), control_id(1)))
    session$setInputs(retrieve = 2L)
    expect_equal(nrow(rv$results), 2)
    expect_null(rv$result_error)
  })
})

test_that("automatic availability failures can be retried without manual refresh", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    do.call(session$setInputs, stats::setNames(list("X", "index"), c(control_id(1), control_id(2))))
    f$log$fail_values <- TRUE
    session$setInputs(retrieve = 1L)
    expect_match(rv$result_error, "Availability API failure")
    expect_null(rv$results)
    expect_identical(query()$filters, list(METRIC = "index", REGION = "X"))
    f$log$fail_values <- FALSE
    session$setInputs(retrieve = 2L)
    expect_equal(nrow(rv$results), 2)
    expect_null(rv$result_error)
  })
})

test_that("broad and malformed queries are checked before automatic API requests", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    do.call(session$setInputs, stats::setNames(list("X"), control_id(1)))
    before <- length(f$log$calls)
    session$setInputs(retrieve = 1L, broad_ok = FALSE)
    expect_equal(length(f$log$calls), before)
    session$setInputs(time_mode = "latest", latest = -1, broad_ok = TRUE, retrieve = 2L)
    expect_match(rv$result_error, "positive integer")
    expect_equal(length(f$log$calls), before)
  })
})

test_that("one edited dimension refreshes only the other dependent code list", {
  f <- fixture_api()
  messages <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(updateSelectizeInput = function(session, inputId,
                                                                  choices = NULL, selected = NULL, ...) {
    messages[[inputId]] <<- list(choices = choices, selected = selected)
  }, .package = "shiny")
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    do.call(session$setInputs, stats::setNames(list("X"), control_id(1)))
    rm(list = ls(messages), envir = messages)
    before <- length(f$log$calls)
    session$setInputs(broad_ok = TRUE, retrieve = 1L)
    calls <- f$log$calls[seq.int(before + 1L, length(f$log$calls))]
    expect_identical(vapply(calls, `[[`, character(1), "kind"), c("values", "data"))
    expect_identical(calls[[1]]$dimension, "METRIC")
    expect_identical(names(messages), control_id(2))
    expect_identical(query()$filters$REGION, "X")
  })
})
