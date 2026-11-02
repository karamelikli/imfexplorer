explorer_server <- function(agency_id, api) {
  force(api); force(agency_id)
  function(input, output, session) {
    cache <- new.env(parent = emptyenv())
    rv <- shiny::reactiveValues(catalog = NULL, catalog_error = NULL, dataset = NULL,
      dimensions = NULL, values = list(), value_errors = list(), availability_keys = list(),
      seed = list(), generation = 0L, results = NULL, result_query = NULL,
      result_dimensions = NULL, result_error = NULL)
    clear_observers <- list()
    notify <- function(text, type = "error") shiny::showNotification(text, type = type, duration = 12)
    control_id <- function(i) paste0("dim_", rv$generation, "_", i)
    non_time <- shiny::reactive({
      d <- rv$dimensions
      if (is.null(d)) return(data.frame(id = character(), name = character()))
      d[!d$is_time, , drop = FALSE]
    })
    filters <- shiny::reactive({
      d <- non_time()
      out <- lapply(seq_len(nrow(d)), function(i) {
        id <- control_id(i)
        if (id %in% names(input)) input[[id]] else rv$seed[[d$id[i]]]
      })
      names(out) <- d$id
      canonical_filters(out)
    })
    query <- shiny::reactive({
      shiny::req(rv$dataset)
      mode <- input$time_mode
      text_or_null <- function(x) if (is.null(x) || !nzchar(trimws(x))) NULL else trimws(x)
      attrs <- if (is.null(input$attributes) || !nzchar(trimws(input$attributes))) character() else
        trimws(strsplit(input$attributes, ",", fixed = TRUE)[[1]])
      new_query(rv$dataset$agency[[1]], rv$dataset$id[[1]], rv$dataset$version[[1]], filters(),
        if (identical(mode, "range")) text_or_null(input$start) else NULL,
        if (identical(mode, "range")) text_or_null(input$end) else NULL,
        if (identical(mode, "latest")) input$latest else NULL, attrs)
    })
    reset_dataset <- function() {
      for (o in clear_observers) o$destroy()
      clear_observers <<- list()
      fresh <- empty_dataset_state()
      rv$dataset <- fresh$dataset; rv$dimensions <- fresh$dimensions
      rv$values <- fresh$values; rv$seed <- fresh$filters
      rv$availability_keys <- list(); rv$value_errors <- list()
      rv$results <- fresh$results; rv$result_query <- fresh$result_query
      rv$result_dimensions <- NULL; rv$result_error <- NULL
      rv$generation <- rv$generation + 1L
      shiny::updateRadioButtons(session, "time_mode", selected = "all")
      shiny::updateTextInput(session, "start", value = "")
      shiny::updateTextInput(session, "end", value = "")
      shiny::updateTextInput(session, "attributes", value = "")
      shiny::updateNumericInput(session, "latest", value = 12)
      shiny::updateCheckboxInput(session, "broad_ok", value = FALSE)
    }
    load_catalog <- function(agency, refresh = FALSE) {
      if (!scalar_text(agency)) { notify("Enter an agency ID."); return(FALSE) }
      if (refresh) rm(list = ls(cache, all.names = TRUE), envir = cache)
      ans <- attempt(cached(cache, cache_key("datasets", list(agency = agency)), function() api$datasets(agency)))
      rv$catalog_error <- ans$error
      rv$catalog <- if (ans$ok) ans$value else NULL
      if (!ans$ok) notify(paste("Catalogue request failed:", ans$error))
      ans$ok
    }
    push_values <- function(q) {
      d <- non_time()
      for (i in seq_len(nrow(d))) {
        choices <- dimension_choices(rv$values[[d$id[i]]], q$filters[[d$id[i]]])
        shiny::updateSelectizeInput(session, control_id(i), choices = choices,
                                   selected = q$filters[[d$id[i]]], server = TRUE)
      }
    }
    update_values <- function(q = shiny::isolate(query())) {
      d <- shiny::isolate(non_time())
      vals <- shiny::isolate(rv$values); errs <- list(); keys <- list()
      shiny::withProgress(message = "Updating available dimension values", value = 0, {
        for (i in seq_len(nrow(d))) {
          dimension <- d$id[i]
          k <- cache_key("values", q, dimension)
          ans <- attempt(cached(cache, k, function() api$values(q, dimension)))
          keys[[dimension]] <- if (ans$ok) k else NULL
          errs[[dimension]] <- ans$error
          if (ans$ok) vals[[dimension]] <- ans$value
          shiny::incProgress(1 / max(1, nrow(d)))
        }
      })
      rv$values <- vals; rv$value_errors <- errs; rv$availability_keys <- keys
      push_values(q)
    }
    select_all_dimension <- function(i) {
      q <- query(); dim <- non_time()$id[i]
      key <- cache_key("values", q, dim)
      # A stale list must be checked under the current other-dimension filters.
      if (!identical(rv$availability_keys[[dim]], key)) {
        ans <- shiny::withProgress(message = paste("Loading available codes for", dim), value = 0.5,
          attempt(cached(cache, key, function() api$values(q, dim))))
        rv$value_errors[[dim]] <- ans$error
        rv$availability_keys[[dim]] <- if (ans$ok) key else NULL
        if (!ans$ok) { notify(paste("Cannot select all for", dim, ":", ans$error)); return() }
        rv$values[[dim]] <- ans$value
      }
      values <- rv$values[[dim]]
      selected <- union(q$filters[[dim]], values$code)
      if (!nrow(values)) notify(paste("No available codes for", dim, "under the current filters."), "warning")
      shiny::updateSelectizeInput(session, control_id(i),
        choices = dimension_choices(values, selected), selected = selected, server = TRUE)
    }
    choose_dataset <- function(row, restore = NULL) {
      reset_dataset()
      rv$dataset <- row
      q <- new_query(row$agency[[1]], row$id[[1]], row$version[[1]])
      ans <- attempt(cached(cache, cache_key("dimensions", q), function() api$dimensions(q)))
      if (!ans$ok) { notify(paste("Dimensions request failed:", ans$error)); return(FALSE) }
      rv$dimensions <- ans$value
      if (!is.null(restore)) {
        valid <- attempt(validate_query(restore, rv$dimensions))
        if (!valid$ok) { notify(valid$error); return(FALSE) }
        rv$seed <- restore$filters
        shiny::updateRadioButtons(session, "time_mode", selected = if (!is.null(restore$last_n_obs)) "latest" else
          if (!is.null(restore$start_period) || !is.null(restore$end_period)) "range" else "all")
        shiny::updateTextInput(session, "start", value = if (is.null(restore$start_period)) "" else restore$start_period)
        shiny::updateTextInput(session, "end", value = if (is.null(restore$end_period)) "" else restore$end_period)
        if (!is.null(restore$last_n_obs)) shiny::updateNumericInput(session, "latest", value = restore$last_n_obs)
        shiny::updateTextInput(session, "attributes", value = paste(restore$attributes, collapse = ", "))
        q <- restore
      }
      d <- non_time()
      for (i in seq_len(nrow(d))) local({
        j <- i; id <- control_id(j); dim <- d$id[j]
        clear_observers[[length(clear_observers) + 1L]] <<- shiny::observeEvent(input[[paste0(id, "_clear")]], {
          shiny::updateSelectizeInput(session, id, selected = character())
        }, ignoreInit = TRUE)
        clear_observers[[length(clear_observers) + 1L]] <<- shiny::observeEvent(input[[paste0(id, "_all")]], {
          select_all_dimension(j)
        }, ignoreInit = TRUE)
        output[[paste0(id, "_status")]] <- shiny::renderUI({
          current <- query()
          v <- rv$values[[dim]]
          err <- rv$value_errors[[dim]]
          if (is.null(v)) v <- data.frame(code = character())
          status <- selection_status(current$filters[[dim]], v, err)
          stale <- !identical(rv$availability_keys[[dim]], cache_key("values", current, dim))
          shiny::tags$div(role = "status", style = if (length(status$invalid) || !is.null(err)) "color:#a12622;" else NULL,
            status$message, if (stale) shiny::tags$strong(" Availability needs updating for the current filters."))
        })
      })
      update_values(q)
      bslib::nav_select("stage", "dimensions", session = session)
      TRUE
    }
    shiny::observeEvent(TRUE, load_catalog(agency_id), once = TRUE)
    shiny::observeEvent(input$load, {
      reset_dataset()
      load_catalog(trimws(input$agency), refresh = TRUE)
    })
    clear_current_query <- function() {
      reset_dataset()
      shiny::updateTextInput(session, "dataset_search", value = "")
      proxy <- DT::dataTableProxy("datasets", session = session)
      DT::selectRows(proxy, NULL)
      DT::updateSearch(proxy, keywords = list(global = ""))
      bslib::nav_select("stage", "dataset", session = session)
    }
    shiny::observeEvent(input$reset, clear_current_query())
    shiny::observeEvent(input$clear_query, clear_current_query())
    shiny::observeEvent(input$dataset_search, {
      DT::updateSearch(DT::dataTableProxy("datasets", session = session),
                       keywords = list(global = input$dataset_search))
    }, ignoreInit = TRUE)
    shiny::observeEvent(input$refresh, {
      row <- rv$dataset
      saved <- if (!is.null(row) && !is.null(rv$dimensions)) query() else NULL
      agency <- if (!is.null(row)) row$agency[[1]] else input$agency
      if (load_catalog(agency, refresh = TRUE) && !is.null(row)) {
        matches <- which(rv$catalog$agency == row$agency[[1]] & rv$catalog$id == row$id[[1]] & rv$catalog$version == row$version[[1]])
        if (!length(matches)) { reset_dataset(); notify("Selected dataset/version is no longer in the catalogue.") } else
          choose_dataset(rv$catalog[matches[1], , drop = FALSE], saved)
      }
    })
    shiny::observeEvent(input$datasets_rows_selected, {
      i <- input$datasets_rows_selected
      if (length(i) == 1L && !is.null(rv$catalog) && i <= nrow(rv$catalog))
        choose_dataset(rv$catalog[i, , drop = FALSE])
    })
    shiny::observeEvent(input$update, { shiny::req(rv$dimensions); update_values() })
    # renderUI inputs bind in the browser after the server's output flush.
    # Register remote selectize sources only after that browser acknowledges them.
    shiny::observeEvent(input$dimensions_ready, {
      if (!identical(as.integer(input$dimensions_ready), rv$generation)) return()
      push_values(query())
    })
    shiny::observeEvent(input$import, {
      result <- attempt({
        if (input$import$size > 1024^2) stop("Configuration is larger than 1 MB.")
        cfg <- parse_config(paste(readLines(input$import$datapath, warn = FALSE), collapse = "\n"))
        cat <- cached(cache, cache_key("datasets", list(agency = cfg$agency)), function() api$datasets(cfg$agency))
        matches <- which(cat$agency == cfg$agency & cat$id == cfg$dataset & cat$version == cfg$version)
        if (!length(matches)) stop("Unavailable dataset or version: ", cfg$agency, "/", cfg$dataset, "/", cfg$version)
        row <- cat[matches[1], , drop = FALSE]
        dims <- cached(cache, cache_key("dimensions", cfg), function() api$dimensions(cfg))
        validate_query(cfg, dims)
        rv$catalog <- cat; rv$catalog_error <- NULL
        shiny::updateTextInput(session, "agency", value = cfg$agency)
        choose_dataset(row, cfg)
      })
      if (!result$ok) notify(paste("Import failed:", result$error)) else
        notify("Configuration restored. Review flagged codes and update availability before retrieving.", "message")
    })
    output$catalog_status <- shiny::renderUI({
      if (!is.null(rv$catalog_error)) shiny::tags$p(role = "alert", paste("Catalogue API failure:", rv$catalog_error)) else
        if (!is.null(rv$catalog) && !nrow(rv$catalog)) shiny::tags$p("No datasets were returned for this agency.")
    })
    output$datasets <- DT::renderDT({
      shiny::req(rv$catalog)
      DT::datatable(rv$catalog[c("agency", "id", "name", "description", "version")],
                    rownames = FALSE, selection = "single", escape = TRUE,
                    options = list(pageLength = 10, scrollX = TRUE, searching = TRUE,
                      dom = "<'imf-hidden-filter'f>lrtip", search = list(search = shiny::isolate(
                        if (is.null(input$dataset_search)) "" else input$dataset_search))))
    }, server = TRUE)
    output$metadata <- shiny::renderUI({
      shiny::req(rv$dataset)
      r <- rv$dataset
      shiny::tagList(shiny::h4(readable(r$name, r$id)), shiny::p(r$description),
        shiny::p(paste("Agency:", r$agency, "Version:", r$version)),
        if (is.null(rv$dimensions)) shiny::p("Dimensions unavailable. Use refresh to retry."))
    })
    output$dimension_controls <- shiny::renderUI({
      d <- non_time()
      if (is.null(rv$dataset)) return(shiny::p("Choose a dataset first."))
      if (is.null(rv$dimensions)) return(shiny::p("Dimensions could not be loaded. Refresh to retry."))
      if (!nrow(d)) return(shiny::p("No non-time dimensions in this dataset."))
      shiny::tagList(shiny::tags$script(shiny::HTML(sprintf(
        "setTimeout(function(){Shiny.setInputValue('dimensions_ready', %d, {priority:'event'});}, 0);",
        rv$generation))), lapply(seq_len(nrow(d)), function(i) {
        id <- control_id(i)
        shiny::wellPanel(shiny::selectizeInput(id, readable(d$name[i], d$id[i]),
          choices = shiny::isolate(rv$seed[[d$id[i]]]), selected = shiny::isolate(rv$seed[[d$id[i]]]), multiple = TRUE,
          options = list(placeholder = "Unrestricted \u2014 search to select codes", maxOptions = 200,
                         plugins = list("remove_button"))),
          shiny::actionButton(paste0(id, "_all"), "Select all available"),
          shiny::actionButton(paste0(id, "_clear"), "Clear selection"), shiny::uiOutput(paste0(id, "_status")))
      }))
    })
    output$summary <- shiny::renderUI({
      if (is.null(rv$dataset)) return(shiny::p("Choose a dataset to begin."))
      q <- query(); d <- non_time()
      shiny::tagList(shiny::strong(readable(rv$dataset$name, q$dataset)),
        shiny::p(paste("Agency:", q$agency, " \u00b7 Version:", q$version)),
        lapply(seq_len(nrow(d)), function(i) {
          id <- d$id[i]; selected <- q$filters[[id]]; v <- rv$values[[id]]
          labels <- if (!length(selected)) "Unrestricted" else if (is.null(v)) paste(selected, collapse = ", ") else
            paste(readable(v$name[match(selected, v$code)], selected), collapse = ", ")
          shiny::p(shiny::strong(readable(d$name[i], id)), shiny::br(), labels)
        }), shiny::p(if (!is.null(q$last_n_obs)) paste("Latest", q$last_n_obs, "per series") else
          paste("Time:", if (is.null(q$start_period)) "unbounded" else q$start_period, "to",
                if (is.null(q$end_period)) "unbounded" else q$end_period)),
        if (length(q$attributes)) shiny::p(paste("Attributes:", paste(q$attributes, collapse = ", "))))
    })
    query_problem <- shiny::reactive({
      if (is.null(rv$dataset) || is.null(rv$dimensions)) return("Choose a dataset with successfully loaded dimensions.")
      q <- query(); valid <- attempt(validate_query(q, rv$dimensions))
      if (!valid$ok) return(valid$error)
      for (dim in non_time()$id) {
        if (!is.null(rv$value_errors[[dim]])) return(paste("Availability API failure for", dim, "\u2014 retry Update available values."))
        if (!identical(rv$availability_keys[[dim]], cache_key("values", q, dim)))
          return("Selections changed. Click Update available values before retrieval.")
        v <- rv$values[[dim]]
        if (is.null(v)) return(paste("Load available values for", dim))
        invalid <- setdiff(q$filters[[dim]], v$code)
        if (length(invalid)) return(paste("Unavailable codes for", dim, ":", paste(invalid, collapse = ", ")))
        if (!nrow(v)) return(paste("No available values for", dim, "under the current filters."))
      }
      NULL
    })
    output$validation <- shiny::renderUI({
      p <- query_problem()
      shiny::p(if (is.null(p)) "Query is valid. Review the code and proceed to Retrieve & export." else p)
    })
    output$code <- shiny::renderText({
      shiny::req(rv$dataset)
      a <- attempt(query_code(query()))
      if (a$ok) a$value else paste("Correct query inputs:", a$error)
    })
    output$breadth <- shiny::renderUI({
      shiny::req(rv$dimensions)
      if (broad_query(query(), rv$dimensions)) shiny::tags$p(role = "alert",
        "Potentially broad request: dimensions/time may be unrestricted or many codes are selected. Latest N limits observations per series only. Code combinations are not a count of available series.")
    })
    # Any query change revokes previous broad-request acknowledgement.
    shiny::observeEvent(query(), shiny::updateCheckboxInput(session, "broad_ok", value = FALSE), ignoreInit = TRUE)
    shiny::observeEvent(input$retrieve, {
      problem <- query_problem()
      if (!is.null(problem)) { notify(problem); return() }
      q <- query()
      if (broad_query(q, rv$dimensions) && !isTRUE(input$broad_ok)) {
        notify("Confirm the broad-request warning before retrieving."); return()
      }
      ans <- shiny::withProgress(message = "Retrieving IMF observations", value = 0.5, attempt(api$data(q)))
      rv$result_error <- ans$error
      if (!ans$ok) { notify(paste("Retrieval failed:", ans$error)); return() }
      rv$results <- ans$value; rv$result_query <- q; rv$result_dimensions <- rv$dimensions
    })
    output$result_status <- shiny::renderUI({
      shiny::tagList(
        if (!is.null(rv$result_error)) shiny::p(role = "alert", paste("Latest retrieval failed:", rv$result_error)),
        if (!is.null(rv$results)) {
          count <- series_info(rv$results, rv$result_dimensions)$count
          shiny::tagList(shiny::p(paste(nrow(rv$results), "returned observations;", if (is.na(count)) "series count unavailable" else paste(count, "returned series"))),
            shiny::p(paste("Result:", rv$result_query$agency, rv$result_query$dataset, rv$result_query$version)),
            if (!same_query(query(), rv$result_query)) shiny::tags$strong(role = "alert", "EARLIER QUERY: these results and CSV/RDS downloads belong to an earlier selection. Retrieve again to update."),
            shiny::tags$details(shiny::tags$summary("Query used for these results"), shiny::tags$pre(query_code(rv$result_query))))
        } else shiny::p("No data retrieved in this dataset selection."))
    })
    output$results <- DT::renderDT({
      shiny::req(rv$results)
      DT::datatable(rv$results, rownames = FALSE, escape = TRUE,
                    options = list(pageLength = 25, scrollX = TRUE))
    }, server = TRUE)
    plan <- shiny::reactive({ shiny::req(rv$results); plot_plan(rv$results, rv$result_dimensions) })
    output$plot_status <- shiny::renderUI({ shiny::req(rv$results); shiny::p(plan()$message) })
    output$plot_container <- shiny::renderUI({
      shiny::req(rv$results)
      p <- plan()
      if (p$ok) shiny::plotOutput("series_plot", height = paste0(max(300, length(p$groups) * 230), "px"))
    })
    output$series_plot <- shiny::renderPlot({ shiny::req(plan()$ok); draw_series(rv$results, plan()) })
    output$csv <- shiny::downloadHandler(filename = function() "imf-data.csv", content = function(file) {
      shiny::req(rv$results); utils::write.csv(rv$results, file, row.names = FALSE, na = "")
    })
    output$rds <- shiny::downloadHandler(filename = function() "imf-data.rds", content = function(file) {
      shiny::req(rv$results); saveRDS(rv$results, file)
    })
    output$script <- shiny::downloadHandler(filename = function() "imf-query.R", content = function(file) {
      writeLines(query_code(query()), file, useBytes = TRUE)
    })
    output$config <- shiny::downloadHandler(filename = function() "imf-query.json", content = function(file) {
      writeLines(query_json(query()), file, useBytes = TRUE)
    })
  }
}
