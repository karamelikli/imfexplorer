#' Build the staged IMF explorer interface
#'
#' Create the sidebar query summary and the dataset, dimension, time, review,
#' retrieval and export stages, including session-bound input and output IDs.
#'
#' @param agency_id Character scalar identifying the initial IMF maintainer.
#' @return A Shiny HTML page produced by [bslib::page_sidebar()]. Constructing
#'   the interface does not retrieve IMF metadata or observations.
#' @seealso [explorer_server()], [explorer_styles()]
#'
#' @keywords internal
explorer_ui <- function(agency_id) {
  bslib::page_sidebar(
    title = "IMF Explorer",
    theme = bslib::bs_theme(version = 5, primary = "#0f766e", bg = "#f5f7fa", fg = "#172b3a"),
    sidebar = bslib::sidebar(
      width = 340,
      shiny::h4("Current query"), shiny::uiOutput("summary"),
      shiny::actionButton("clear_query", "Clear current query", icon = shiny::icon("eraser")),
      shiny::hr(), shiny::fileInput("import", "Restore query JSON", accept = ".json"),
      shiny::helpText("Metadata are requested on demand. Observations are fetched only with Retrieve data.")
    ),
    # DT's proxy search API needs its native search element in the DOM.
    explorer_styles(),
    bslib::navset_card_tab(
      id = "stage",
      bslib::nav_panel("1 \u00b7 Dataset",
        value = "dataset",
        shiny::fluidRow(
          shiny::column(6, shiny::textInput("agency", "Agency ID", agency_id)),
          shiny::column(
            6, shiny::br(), shiny::actionButton("load", "Load / refresh catalogue"),
            shiny::actionButton("reset", "Reset")
          )
        ),
        shiny::actionButton("refresh", "Clear metadata cache / refresh selected dataset"),
        shiny::textInput("dataset_search", "Search datasets",
          placeholder = "Search dataset IDs, names, descriptions or versions"
        ),
        shiny::uiOutput("catalog_status"), DT::DTOutput("datasets"),
        shiny::helpText("Search IDs, names, descriptions or versions; select one row."),
        shiny::uiOutput("metadata")
      ),
      bslib::nav_panel("2 \u00b7 Dimensions",
        value = "dimensions",
        shiny::tags$div(
          class = "imf-selection-page",
          shiny::tags$header(
            class = "imf-selection-header",
            shiny::tags$span(class = "imf-eyebrow", "BUILD YOUR QUERY"),
            shiny::h2("Choose your dimensions"),
            shiny::p("Search for values in any order. Leave a dimension empty to include all its available values."),
            shiny::uiOutput("dimension_overview")
          ),
          shiny::tags$div(
            class = "imf-selection-toolbar",
            shiny::tags$div(
              shiny::icon("circle-info"),
              shiny::tags$span(paste(
                "Availability is checked automatically when you retrieve data.",
                "Refresh to explore matching choices."
              ))
            ),
            shiny::actionButton("update", "Update available values",
              icon = shiny::icon("arrows-rotate"), class = "btn-outline-primary"
            )
          ),
          shiny::uiOutput("dimension_controls"),
          shiny::tags$footer(
            class = "imf-selection-footer",
            shiny::tags$span("Remove any selected item with its x button. Your choices stay editable."),
            shiny::actionButton("next_time", "Continue to time options",
              icon = shiny::icon("arrow-right"), class = "btn-primary"
            )
          )
        )
      ),
      bslib::nav_panel("3 \u00b7 Time",
        value = "time",
        shiny::radioButtons(
          "time_mode", "Time filter",
          c("All periods" = "all", "Period range" = "range", "Latest N per series" = "latest")
        ),
        shiny::conditionalPanel(
          "input.time_mode == 'range'",
          shiny::textInput("start", "Start (optional)", placeholder = "2020 or 2020-Q1 or 2020-01"),
          shiny::textInput("end", "End (optional)", placeholder = "2025-12")
        ),
        shiny::conditionalPanel(
          "input.time_mode == 'latest'",
          shiny::numericInput("latest", "Latest N observations per series", 12, min = 1, step = 1)
        ),
        shiny::helpText(paste(
          "Time modes are mutually exclusive: latest N ignores the inactive range fields.",
          "Bounds accept YYYY, YYYY-Qn, YYYY-MM or YYYY-MM-DD.",
          "N is per series, not a total row limit."
        )),
        shiny::textInput("attributes", "Optional attribute IDs (comma separated)",
          placeholder = "Exact IDs from this dataset, e.g. UNIT_MEASURE"
        ),
        shiny::helpText(paste(
          "Attributes are dataset-specific.",
          "Unknown IDs produce an API error; none are requested by default."
        ))
      ),
      bslib::nav_panel("4 \u00b7 Review",
        value = "review",
        shiny::uiOutput("validation"), shiny::h4("Runnable R code"),
        shiny::tags$pre(style = "white-space:pre-wrap;", shiny::textOutput("code")),
        shiny::downloadButton("script", "Download R script"),
        shiny::downloadButton("config", "Download query JSON")
      ),
      bslib::nav_panel("5 \u00b7 Retrieve & export",
        value = "retrieve",
        shiny::checkboxInput(
          "exclude_unavailable", "Exclude unavailable or unverified selections before retrieval", FALSE
        ),
        shiny::helpText(paste(
          "Remaining codes are checked again before retrieval. Excluded codes are reported below.",
          "If a dimension loses every selected code, choose an available value or explicitly clear it to continue.",
          "Metadata failures must be resolved before retrieval."
        )),
        shiny::uiOutput("breadth"),
        shiny::checkboxInput("broad_ok", "I understand this may request many series / observations", FALSE),
        shiny::actionButton("retrieve", "Retrieve data", class = "btn-primary"),
        shiny::tags$div(
          class = "imf-results-layout",
          shiny::uiOutput("result_status"),
          shiny::tags$div(class = "imf-results-table", DT::DTOutput("results", fill = FALSE)),
          shiny::tags$section(
            class = "imf-export-section", `aria-label` = "Download retrieved data",
            shiny::h4("Download data"),
            shiny::tags$div(
              class = "imf-export-actions",
              shiny::downloadButton("csv", "Download CSV"), shiny::downloadButton("rds", "Download RDS")
            ),
            shiny::helpText(paste(
              "CSV/RDS export the displayed result, including when marked as an earlier query.",
              "The script and JSON describe the current query."
            ))
          ),
          shiny::uiOutput("plot_status"), shiny::uiOutput("plot_container")
        )
      )
    )
  )
}
