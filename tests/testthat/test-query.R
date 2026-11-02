test_that("code serializes hostile strings safely without execution", {
  q <- new_query('A"\\\n', 'B"; stop("injected") #', "1", list(REGION = c('X"', "Y\\n")), last_n_obs = 2)
  code <- query_code(q)
  expr <- parse(text = code)
  expect_length(expr, 2)
  expect_identical(expr[[1]][[3]], parse(text = paste(deparse(q$filters), collapse = "\n"))[[1]])
  expect_identical(expr[[2]][[3]][[1]], quote(imf.data::get_data))
  expect_identical(expr[[2]][[3]]$dataflow, q$dataset)
  expect_identical(expr[[2]][[3]]$agency_id, q$agency)
  expect_identical(expr[[2]][[3]]$filters, quote(filters))
  expect_identical(expr[[2]][[3]]$last_n_obs, 2)
})

test_that("JSON round trips preserve vectors, nulls and exact identities", {
  for (q in list(new_query("TEST", "A", "1"),
    new_query("TEST", "A", "1", list(REGION = "X"), last_n_obs = 12),
    new_query("TEST", "B", "2", list(SECTOR = c("S1", "S2")), start_period = "2020-Q1", attributes = "UNIT"))) {
    expect_identical(parse_config(query_json(q)), q)
  }
  expect_error(parse_config('{"schema_version":2}'), "schema")
  expect_error(parse_config('{"unknown":1}'), "fields")
  expect_error(parse_config('{"schema_version":1,"agency":"A","dataset":"B","version":"1","filters":{"X":2}}'), "codes")
  q <- new_query("TEST", "A", "1", list(UNKNOWN = "X"))
  expect_error(validate_query(q, fixture_api()$api$dimensions(q)), "Unavailable")
})

test_that("validation rejects conflicting and invalid time options", {
  expect_error(validate_query(new_query("T", "A", "1", start_period = "2024", end_period = "2020")), "precede")
  expect_error(validate_query(new_query("T", "A", "1", start_period = "2024", last_n_obs = 2)), "not both")
  expect_error(validate_query(new_query("T", "A", "1", last_n_obs = 1.5)), "integer")
  expect_error(validate_query(new_query("T", "A", "1", start_period = "2024-02-31")), "use YYYY")
  expect_equal(period_number("2024-M02"), period_number("2024-02"))
})

test_that("plot groups by dimensions and units without changing values", {
  f <- fixture_api(); q <- new_query("T", "A", "1")
  d <- f$api$data(q); dims <- f$api$dimensions(q)
  plan <- plot_plan(d, dims)
  expect_true(plan$ok); expect_length(plan$groups, 1)
  expect_identical(d$OBS_VALUE, c(100, 102))
  d <- rbind(d, transform(d, UNIT_MEASURE = "USD"))
  expect_length(plot_plan(d, dims)$groups, 2)
  expect_false(plot_plan(rbind(d, d), dims)$ok)
  expect_false(plot_plan(d[, setdiff(names(d), "METRIC")], dims)$ok)
  expect_equal(series_info(d[0, ], dims)$count, 0)
  d$TIME_PERIOD <- "unrecognized"
  expect_false(plot_plan(d, dims)$ok)
})
