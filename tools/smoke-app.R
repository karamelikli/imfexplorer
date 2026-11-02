# Local browser smoke harness. Uses explicitly SYNTHETIC fixtures, never IMF results.
pkgload::load_all(".", quiet = TRUE)
source("tests/testthat/helper-fixtures.R")
shiny::runApp(explorer_app("TEST", fixture_api()$api), host = "127.0.0.1", port = 7854,
              launch.browser = FALSE)
