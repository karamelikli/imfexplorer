test_that("column descriptions and exact code labels survive RDS and Excel export", {
  q <- new_query("TEST", "EXAMPLE", "1")
  urn <- function(kind, id, member = "") {
    paste0("urn:sdmx:org.sdmx.infomodel.", kind, "=TEST:", id, "(1.0)", member)
  }
  concept <- function(id, name, description, codelist = NULL) {
    list(
      id = id, name = name, description = description,
      coreRepresentation = if (!is.null(codelist)) list(enumeration = urn("codelist.Codelist", codelist))
    )
  }
  component <- function(id) list(id = id, conceptIdentity = urn("conceptscheme.Concept", "CS", paste0(".", id)))
  structure <- list(data = list(
    dataStructures = list(list(dataStructureComponents = list(
      dimensionList = list(
        dimensions = list(component("COUNTRY"), component("ADJUSTMENT")),
        timeDimensions = list(component("TIME_PERIOD"))
      ),
      measureList = list(measures = list(component("OBS_VALUE"))),
      attributeList = list(attributes = list(component("UNIT")))
    ))),
    conceptSchemes = list(list(agencyID = "TEST", id = "CS", version = "1.0", concepts = list(
      concept("COUNTRY", "Geography", "Geographic coverage of the observation.", "CL_COUNTRY"),
      concept("ADJUSTMENT", "Seasonal adjustment", "Seasonal adjustment status.", "CL_ADJUSTMENT"),
      concept("TIME_PERIOD", "Time period", "Reporting period."),
      concept("OBS_VALUE", "Observation value", "Published index level."),
      concept("UNIT", "Unit of measure", "Units used for the observation.", "CL_UNIT")
    ))),
    codelists = list(
      list(agencyID = "TEST", id = "CL_COUNTRY", version = "1.0", codes = list(
        list(id = "G001", name = "World", description = "All economies combined.")
      )),
      list(agencyID = "TEST", id = "CL_ADJUSTMENT", version = "1.0", codes = list(
        list(id = "NSA", name = "Not seasonally adjusted (NSA)", description = "No seasonal adjustment applied.")
      )),
      list(agencyID = "TEST", id = "CL_UNIT", version = "1.0", codes = list(list(id = "IX", name = "Index points")))
    )
  ))
  data <- data.frame(COUNTRY = "G001", ADJUSTMENT = "NSA", TIME_PERIOD = "2026-M01", OBS_VALUE = 123L, UNIT = "IX")
  attr(data$OBS_VALUE, "units") <- "points"
  dims <- normalize_dimensions(data.frame(
    id = c("COUNTRY", "ADJUSTMENT", "TIME_PERIOD"),
    type = c("Dimension", "Dimension", "TimeDimension")
  ))
  dataset <- normalize_datasets(data.frame(agency = "TEST", id = "EXAMPLE", version = "1"))
  meta <- result_metadata(data, q, dataset, dims, list(), structure = structure)
  labelled <- annotate_result(data, meta)
  expect_identical(attr(labelled$COUNTRY, "label"), "Geography")
  expect_identical(attr(labelled$COUNTRY, "description"), "Geographic coverage of the observation.")
  expect_identical(attr(labelled$COUNTRY, "code_labels"), c(G001 = "World"))
  expect_identical(attr(labelled$ADJUSTMENT, "code_labels"), c(NSA = "Not seasonally adjusted (NSA)"))
  expect_identical(attr(labelled$ADJUSTMENT, "code_descriptions"), c(NSA = "No seasonal adjustment applied."))
  expect_identical(attr(labelled$UNIT, "code_labels"), c(IX = "Index points"))
  expect_identical(attr(labelled$OBS_VALUE, "description"), "Published index level.")
  expect_identical(attr(labelled$TIME_PERIOD, "description"), "Reporting period.")
  expect_identical(attr(labelled$OBS_VALUE, "units"), "points")
  expect_identical(typeof(labelled$OBS_VALUE), "integer")
  expect_identical(as.vector(labelled$OBS_VALUE), as.vector(data$OBS_VALUE))
  expect_identical(as.vector(labelled$COUNTRY), data$COUNTRY)
  file <- tempfile(fileext = ".rds")
  excel <- tempfile(fileext = ".xlsx")
  on.exit(unlink(c(file, excel)))
  saveRDS(labelled, file)
  expect_identical(readRDS(file), labelled)
  if (requireNamespace("readxl", quietly = TRUE)) {
    write_result_excel(labelled, excel)
    codes <- readxl::read_xlsx(excel, sheet = "Codes")
    expect_true("G001: World" %in% codes$definition)
    expect_true("NSA: Not seasonally adjusted (NSA)" %in% codes$definition)
    variables <- readxl::read_xlsx(excel, sheet = "Variables")
    expect_identical(variables$description[variables$variable == "OBS_VALUE"], "Published index level.")
  }
})

test_that("missing definitions retain available labels and do not invent meanings", {
  f <- fixture_api()
  q <- new_query("TEST", "A", "1")
  data <- f$api$data(q)
  data$REGION <- "unknown"
  dims <- f$api$dimensions(q)
  data <- annotate_result(data, result_metadata(
    data, q, f$api$datasets("TEST")[1, ], dims,
    list(REGION = normalize_values(data.frame(code = "X", name = "Known region")))
  ))
  expect_identical(attr(data$REGION, "label"), "REGION")
  expect_true(is.na(attr(data$REGION, "code_labels")[["unknown"]]))
  expect_identical(attr(data$OBS_VALUE, "label"), "Observation value")
  expect_identical(attr(data$TIME_PERIOD, "label"), "TIME_PERIOD")
})
