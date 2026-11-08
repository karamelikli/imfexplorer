test_that("default and explicit foreground launches retain positional arguments and invisible results", {
  captured <- list()
  expected <- list(stopped = TRUE)
  testthat::local_mocked_bindings(runApp = function(appDir, launch.browser) {
    captured[[length(captured) + 1L]] <<- list(app = appDir, browser = launch.browser)
    expected
  }, .package = "shiny")
  testthat::local_mocked_bindings(
    background_explorer = function(...) stop("Unexpected background launch"),
    .package = "imfexplorer"
  )
  first <- withVisible(imfexplorer("TEST", FALSE))
  second <- withVisible(imfexplorer("OTHER", TRUE, FALSE))
  expect_false(first$visible)
  expect_false(second$visible)
  expect_identical(first$value, expected)
  expect_identical(second$value, expected)
  expect_s3_class(captured[[1]]$app, "shiny.appobj")
  expect_identical(captured[[1]]$browser, FALSE)
  expect_identical(captured[[2]]$browser, TRUE)
})

test_that("background requires one non-missing logical value", {
  invalid <- list(NULL, logical(), NA, c(TRUE, FALSE), c(NA, TRUE), 1, 0, "TRUE", list(TRUE))
  for (value in invalid) expect_error(imfexplorer(background = value), "background must be TRUE or FALSE")
  expect_error(imfexplorer(launch.browser = NA, background = TRUE), "launch.browser")
  expect_error(imfexplorer(agency_id = "", background = TRUE), "agency_id")
})

test_that("missing callr is actionable and only background mode needs it", {
  scope <- new.env(parent = environment(background_explorer))
  scope$requireNamespace <- function(...) FALSE
  launch <- background_explorer
  environment(launch) <- scope
  expect_error(launch("TEST", FALSE), 'install.packages("callr")', fixed = TRUE)
})

test_that("startup timeout stops the child and preserves useful diagnostics", {
  skip_if_not_installed("callr")
  path <- tempfile("mock-installed-")
  dir.create(file.path(path, "Meta"), recursive = TRUE)
  file.create(file.path(path, "Meta", "package.rds"))
  on.exit(unlink(path, recursive = TRUE))
  state <- new.env(parent = emptyenv())
  state$alive <- TRUE
  state$waited <- FALSE
  process <- list(
    is_alive = function() state$alive,
    kill = function() state$alive <- FALSE,
    wait = function(timeout) state$waited <- TRUE
  )
  testthat::local_mocked_bindings(randomPort = function(host) 43210L, .package = "httpuv")
  testthat::local_mocked_bindings(r_bg = function(func, args, ..., stdout, stderr) {
    writeLines("Synthetic startup diagnostic", stderr)
    state$stderr <- stderr
    process
  }, .package = "callr")
  error <- tryCatch(background_explorer("TEST", FALSE, startup_timeout = 0, package_path = path), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "timed out")
  expect_match(conditionMessage(error), "Synthetic startup diagnostic")
  expect_match(conditionMessage(error), state$stderr, fixed = TRUE)
  expect_false(state$alive)
  expect_true(state$waited)
  expect_true(file.exists(state$stderr))
})

test_that("child startup errors and parent browser handling are explicit", {
  skip_if_not_installed("callr")
  path <- tempfile("mock-installed-")
  dir.create(file.path(path, "Meta"), recursive = TRUE)
  file.create(file.path(path, "Meta", "package.rds"))
  on.exit(unlink(path, recursive = TRUE))
  state <- new.env(parent = emptyenv())
  state$alive <- FALSE
  state$steps <- character()
  process <- list(
    is_alive = function() state$alive,
    kill = function() state$alive <- FALSE,
    wait = function(timeout) invisible(NULL),
    get_result = function() stop("Synthetic child error")
  )
  testthat::local_mocked_bindings(randomPort = function(host) 43210L, .package = "httpuv")
  testthat::local_mocked_bindings(r_bg = function(func, args, ..., supervise, libpath, stdout, stderr) {
    expect_true(supervise)
    expect_identical(libpath[1], dirname(normalizePath(path)))
    if (state$alive) writeLines(args$token, args$ready_file)
    process
  }, .package = "callr")
  testthat::local_mocked_bindings(background_ready = function(port, timeout) {
    state$steps <- c(state$steps, "ready")
    TRUE
  }, .package = "imfexplorer")
  testthat::local_mocked_bindings(browseURL = function(url) {
    state$steps <- c(state$steps, "browser")
    expect_match(url, "^http://127[.]0[.]0[.]1:43210/$")
  }, .package = "utils")
  expect_error(background_explorer("TEST", FALSE, package_path = path), "Synthetic child error")
  state$alive <- TRUE
  handle <- background_explorer("TEST", TRUE, package_path = path)
  on.exit(handle$stop(), add = TRUE)
  expect_identical(state$steps, c("ready", "browser"))
  expect_true(handle$is_alive())
  handle$stop()
  handle$stop()
  expect_false(handle$is_alive())
})

test_that("an installed package returns while its loopback child runs and stops it", {
  skip_if_not_installed("callr")
  path <- getNamespaceInfo(asNamespace("imfexplorer"), "path")
  skip_if(!file.exists(file.path(path, "Meta", "package.rds")), "Run from an installed package for the process test")
  result <- withVisible(imfexplorer("TEST", launch.browser = FALSE, background = TRUE))
  app <- result$value
  on.exit(app$stop())
  expect_false(result$visible)
  expect_s3_class(app, "imfexplorer_process")
  expect_match(app$url, "^http://127[.]0[.]0[.]1:[0-9]+/$")
  expect_true(app$is_alive())
  expect_identical(1 + 1, 2) # This runs before the child exits.
  port <- as.integer(sub("/$", "", sub("http://127.0.0.1:", "", app$url, fixed = TRUE)))
  expect_true(background_ready(port)) # HTTP only: no Shiny session and no IMF API calls.
  expect_true(file.exists(app$logs$stderr))
  app$stop()
  expect_false(app$is_alive())
  expect_false(background_ready(port, timeout = 0.2))
  expect_invisible(app$stop())
})

test_that("a real timed-out startup cleans up its child", {
  skip_if_not_installed("callr")
  path <- getNamespaceInfo(asNamespace("imfexplorer"), "path")
  skip_if(!file.exists(file.path(path, "Meta", "package.rds")), "Run from an installed package for the process test")
  state <- new.env(parent = emptyenv())
  state$process <- NULL
  create_process <- callr::r_bg
  testthat::local_mocked_bindings(r_bg = function(...) {
    state$process <- create_process(...)
    state$process
  }, .package = "callr")
  on.exit(if (!is.null(state$process)) stop_background(state$process))
  expect_error(background_explorer("TEST", FALSE, startup_timeout = 0), "timed out")
  expect_false(state$process$is_alive())
})
