test_that("optional exclusion retrieves only verified remaining codes", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "latest", latest = 2)
    args <- stats::setNames(list(c("X", "Y", "unknown"), "limited"), c(control_id(1), control_id(2)))
    do.call(session$setInputs, args)
    session$setInputs(retrieve = 1L, broad_ok = TRUE)
    expect_null(rv$results)
    expect_match(rv$result_error, "Unavailable codes")
    session$setInputs(exclude_unavailable = TRUE, retrieve = 2L, broad_ok = TRUE)
    expect_null(rv$result_error)
    expect_equal(nrow(rv$results), 2)
    expect_identical(rv$result_query$filters, list(METRIC = "limited", REGION = "X"))
    expect_match(rv$result_exclusions, "REGION: Y, unknown")
    calls <- Filter(function(x) x$kind == "data", f$log$calls)
    expect_length(calls, 1)
    expect_identical(calls[[1]]$q, rv$result_query)
    expect_null(query_issue(rv$result_query))
    # Browser acknowledgement of the updated selectize selection.
    do.call(session$setInputs, stats::setNames(list("X"), control_id(1)))
    expect_true(same_query(query(), rv$result_query))
    expect_match(output$code, 'REGION = "X"', fixed = TRUE)
  })
})

test_that("exclusion never turns an invalid selected dimension into an unrestricted request", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    do.call(session$setInputs, stats::setNames(list("missing"), control_id(1)))
    session$setInputs(exclude_unavailable = TRUE, retrieve = 1L, broad_ok = TRUE)
    expect_match(rv$result_error, "No verified selected codes remain for REGION")
    expect_null(rv$results)
    expect_identical(query()$filters$REGION, "missing")
    expect_false(any(vapply(f$log$calls, function(x) x$kind == "data", logical(1))))
  })
})

test_that("exclusion does not trust stale metadata after an API failure", {
  f <- fixture_api()
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    do.call(session$setInputs, stats::setNames(list(c("X", "Y")), control_id(1)))
    f$log$fail_values <- TRUE
    rm(list = ls(cache, all.names = TRUE), envir = cache)
    session$setInputs(update = 1L)
    session$setInputs(exclude_unavailable = TRUE, retrieve = 1L, broad_ok = TRUE)
    expect_null(rv$results)
    expect_match(rv$result_error, "No verified selected codes remain")
    f$log$fail_values <- FALSE
    session$setInputs(retrieve = 2L, broad_ok = TRUE)
    expect_null(rv$result_error)
    expect_equal(nrow(rv$results), 2)
    expect_length(rv$result_exclusions, 0)
  })
})

test_that("changed availability is rechecked after each exclusion", {
  f <- fixture_api()
  original_values <- f$api$values
  f$api$values <- function(q, dimension) {
    if (dimension == "METRIC" && identical(q$filters$REGION, "X")) {
      return(normalize_values(data.frame(code = "limited")))
    }
    original_values(q, dimension)
  }
  shiny::testServer(explorer_server("TEST", f$api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L)
    args <- stats::setNames(list(c("X", "missing"), c("index", "limited")), c(control_id(1), control_id(2)))
    do.call(session$setInputs, args)
    session$setInputs(exclude_unavailable = TRUE, retrieve = 1L, broad_ok = TRUE)
    expect_null(rv$result_error)
    expect_identical(rv$result_query$filters, list(METRIC = "limited", REGION = "X"))
    expect_length(rv$result_exclusions, 2)
    expect_null(query_issue(rv$result_query))
    session$setInputs(clear_query = 1L)
    expect_length(rv$result_exclusions, 0)
  })
})
