test_that("PI query with unrestricted country, frequency and time retrieves without manual update", {
  # Synthetic offline values/observations. Dimension IDs/types were checked
  # against live PI 2.0.0 metadata; observations here are NOT live IMF data.
  seen <- NULL
  api <- list(
    datasets = function(agency) normalize_datasets(data.frame(
      agency = agency, id = "PI", version = "2.0.0", name = "Synthetic PI fixture")),
    dimensions = function(q) normalize_dimensions(data.frame(
      id = c("COUNTRY", "PRODUCTION_INDEX", "TYPE_OF_TRANSFORMATION", "FREQUENCY", "TIME_PERIOD"),
      type = c(rep("Dimension", 4), "TimeDimension"))),
    values = function(q, dimension) normalize_values(data.frame(code = switch(dimension,
      COUNTRY = c("USA", "CAN"), PRODUCTION_INDEX = "IND", TYPE_OF_TRANSFORMATION = "IX",
      FREQUENCY = c("A", "M")))),
    data = function(q) {
      seen <<- q
      data.frame(COUNTRY = "USA", PRODUCTION_INDEX = "IND", TYPE_OF_TRANSFORMATION = "IX",
        FREQUENCY = "M", TIME_PERIOD = "2024-M01", OBS_VALUE = 123)
    }
  )
  shiny::testServer(explorer_server("IMF.STA", api), {
    session$flushReact()
    session$setInputs(datasets_rows_selected = 1L, time_mode = "all")
    do.call(session$setInputs, stats::setNames(list("IND", "IX"), c(control_id(2), control_id(3))))
    expect_match(query_problem(), "automatically")
    session$setInputs(broad_ok = TRUE, retrieve = 1L)
    expect_null(rv$result_error)
    expect_equal(nrow(rv$results), 1)
    expect_identical(seen$filters, list(PRODUCTION_INDEX = "IND", TYPE_OF_TRANSFORMATION = "IX"))
    expect_identical(seen$dataset, "PI")
    expect_identical(seen$agency, "IMF.STA")
    expect_identical(seen$version, "2.0.0")
    expect_null(seen$start_period)
    expect_null(seen$end_period)
    expect_null(seen$last_n_obs)
    expect_identical(seen$attributes, character())
    expect_null(query_problem())
  })
})
