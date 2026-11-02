test_that("optional live API discovery and narrow versioned data query work", {
  skip_if(Sys.getenv("IMFEXPLORER_LIVE_TESTS") != "true", "Set IMFEXPLORER_LIVE_TESTS=true for live IMF checks")
  api <- imf_adapter()
  catalog <- api$datasets("IMF.STA")
  cpi <- catalog[catalog$id == "CPI", , drop = FALSE]
  expect_gt(nrow(cpi), 0)
  q <- new_query("IMF.STA", "CPI", cpi$version[[1]], list(
    COUNTRY = "USA", INDEX_TYPE = "CPI",
    COICOP_1999 = "_T", TYPE_OF_TRANSFORMATION = "IX", FREQUENCY = "M"
  ), last_n_obs = 2)
  dims <- api$dimensions(q)
  expect_true("TIME_PERIOD" %in% dims$id[dims$is_time])
  vals <- api$values(q, "FREQUENCY")
  expect_true("M" %in% vals$code)
  data <- api$data(q)
  expect_true(all(c("TIME_PERIOD", "OBS_VALUE") %in% names(data)))
  expect_true(is.numeric(data$OBS_VALUE))
  expect_lte(nrow(data), 2)
  expect_true(plot_plan(data, dims)$ok)
})
