test_that("normalization follows the inspected 0.2.0 schema", {
  a <- fixture_api()$api
  expect_identical(a$dimensions(new_query("TEST", "A", "1"))$is_time, c(FALSE, FALSE, TRUE))
  expect_identical(a$dimensions(new_query("TEST", "B", "2"))$id, c("SECTOR", "FREQ", "PERIOD"))
  expect_identical(normalize_values(data.frame(code = character()))$code, character())
  expect_error(normalize_values(NULL), "data frame")
  expect_error(normalize_dimensions(data.frame(id = "X")), "type")
  expect_match(readable(NA_character_, "X"), "X \\[X\\]")
  expect_false(attempt(stop("network down"))$ok)
  expect_true(attempt(data.frame())$ok)
})

test_that("adapter uses exact supported arguments and excludes own filters", {
  seen <- NULL
  testthat::local_mocked_bindings(list_dimension_values = function(dataflow, dimension, filters,
                                                                   agency_id, version) {
    seen <<- as.list(environment())
    data.frame(code = "Y", name = "Label")
  }, .package = "imf.data")
  q <- new_query("TEST", "A", "1", list(REGION = "X", METRIC = "index"))
  imf_adapter()$values(q, "REGION")
  expect_identical(seen$filters, list(METRIC = "index"))
  expect_identical(seen$dataflow, "A")
  expect_identical(seen$agency_id, "TEST")
  expect_identical(seen$version, "1")
})

test_that("cache keys canonicalize filters and distinguish query identities", {
  q <- new_query("TEST", "A", "1", list(REGION = c("Y", "X"), METRIC = "index"))
  r <- q
  r$filters <- list(METRIC = "index", REGION = c("X", "Y"))
  expect_identical(cache_key("values", q, "REGION"), cache_key("values", r, "REGION"))
  r$filters$REGION <- "other"
  expect_identical(cache_key("values", q, "REGION"), cache_key("values", r, "REGION"))
  expect_false(identical(cache_key("values", q, "METRIC"), cache_key("values", r, "METRIC")))
  for (field in c("agency", "dataset", "version")) {
    r <- q
    r[[field]] <- "different"
    expect_false(identical(cache_key("values", q, "REGION"), cache_key("values", r, "REGION")))
  }
  expect_false(identical(cache_key("values", q, "REGION"), cache_key("values", q, "METRIC")))
  cache <- new.env()
  n <- 0
  fetch <- function() {
    n <<- n + 1
    data.frame(code = "X")
  }
  cached(cache, "k", fetch)
  cached(cache, "k", fetch)
  expect_equal(n, 1)
  expect_error(cached(cache, "bad", function() stop("fail")), "fail")
  expect_false(exists("bad", cache))
})

test_that("availability distinguishes empty, invalid and failed responses", {
  empty <- normalize_values(data.frame(code = character()))
  expect_match(selection_status(character(), empty)$message, "No available")
  status <- selection_status(c("X", "Y"), data.frame(code = "X"))
  expect_identical(status$invalid, "Y")
  expect_match(status$message, "clear")
  expect_match(selection_status("X", empty, "timeout")$message, "API failure")
})

test_that("choice sources preserve unavailable codes and handle zero-length labels", {
  expect_identical(
    dimension_choices(normalize_values(data.frame(code = character())), character()),
    stats::setNames(character(), character())
  )
  values <- normalize_values(data.frame(code = "X", name = "Label X"))
  expect_identical(unname(dimension_choices(values, c("X", "Y"))), c("X", "Y"))
  expect_match(names(dimension_choices(values, "Y"))[2], "unavailable")
})

test_that("a sole own-dimension filter has the same availability key as no filters", {
  q <- new_query("TEST", "A", "1")
  r <- new_query("TEST", "A", "1", list(REGION = "X"))
  expect_identical(cache_key("values", q, "REGION"), cache_key("values", r, "REGION"))
  expect_false(identical(cache_key("values", q, "METRIC"), cache_key("values", r, "METRIC")))
})
