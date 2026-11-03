test_that("bundled application resources are available through the package", {
  css <- explorer_file("app", "www", "imfexplorer.css")
  entry <- explorer_file("app", "app.R")
  expect_true(file.exists(css))
  expect_true(file.exists(entry))
  html <- as.character(explorer_styles())
  expect_match(html, "imf-dimension-grid", fixed = TRUE)
  expect_match(html, "imf-export-section", fixed = TRUE)
})

test_that("the source launcher resolves resources from its private package root", {
  root <- tempfile("source-package-")
  dir.create(file.path(root, "inst", "app", "www"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  css <- file.path(root, "inst", "app", "www", "example.css")
  writeLines("body { color: black; }", css)
  env <- new.env(parent = environment(explorer_file))
  env$.imfexplorer_source_root <- root
  env$explorer_file <- explorer_file
  environment(env$explorer_file) <- env
  expect_identical(env$explorer_file("app", "www", "example.css"), normalizePath(css))
  expect_error(env$explorer_file("missing.css"), "resource not found")
})

test_that("the bundled app entry delegates to the application factory", {
  expected <- list(marker = "synthetic app constructor")
  testthat::local_mocked_bindings(explorer_app = function() expected, .package = "imfexplorer")
  result <- source(explorer_file("app", "app.R"), local = new.env())$value
  expect_identical(result, expected)
})
