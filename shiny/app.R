# FraudDetect: corrected risk analytics dashboard
# Run the corrected pipeline from the repository root before launching:
#   source("corrected_r/scripts/01_modeling.R")
#   source("corrected_r/scripts/04_optimize_anomaly_thresholds.R")
#   source("corrected_r/scripts/05_cost_sensitive_alert_optimization.R")
# Then launch with shiny::runApp("shiny/")

library(shiny)
library(bslib)
library(tidyverse)
library(DT)
library(scales)

# Resolve paths whether launched from the repository root or shiny/.
wd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
root <- if (file.exists(file.path(wd, "data", "transactions.csv"))) {
  wd
} else {
  normalizePath(file.path(wd, ".."), winslash = "/", mustWork = TRUE)
}
out_dir <- file.path(root, "corrected_r", "outputs")

read_required <- function(path) {
  if (!file.exists(path)) {
    stop(
      "Required input is missing: ", path,
      "\nRun corrected_r/scripts/01_modeling.R, ",
      "04_optimize_anomaly_thresholds.R, and ",
      "05_cost_sensitive_alert_optimization.R from the repository root."
    )
  }
  readr::read_csv(path, show_col_types = FALSE)
}

raw <- read_required(file.path(root, "data", "transactions.csv"))
model_metrics <- read_required(file.path(out_dir, "model_comparison.csv"))
predictions <- read_required(file.path(out_dir, "test_predictions.csv"))
if_policy <- read_required(file.path(out_dir, "if_threshold_policy_comparison.csv"))
if_scores <- read_required(file.path(out_dir, "if_test_scores.csv"))
costs <- read_required(file.path(out_dir, "cost_sensitive_policy_comparison.csv"))
sensitivity <- read_required(file.path(out_dir, "cost_sensitivity_analysis.csv"))
assumptions <- read_required(file.path(out_dir, "cost_model_assumptions.csv"))

# Validate the corrected pipeline contract before rendering any panels.
required_model <- c("model", "test_roc_auc", "test_pr_auc", "precision",
                    "recall", "specificity", "false_positives", "false_negatives")
required_pred <- c("transaction_id", "actual", "xgboost_probability",
                   "xgboost_predicted")
required_policy <- c("split", "strategy", "alerts", "true_positives",
                     "false_positives", "false_negatives", "precision", "recall")
required_cost <- c("strategy", "alerts", "estimated_total_cost",
                   "total_alert_review_cost", "estimated_missed_fraud_loss")
for (item in list(
  list(data = model_metrics, cols = required_model, name = "model_comparison.csv"),
  list(data = predictions, cols = required_pred, name = "test_predictions.csv"),
  list(data = if_policy, cols = required_policy, name = "if_threshold_policy_comparison.csv"),
  list(data = costs, cols = required_cost, name = "cost_sensitive_policy_comparison.csv")
)) {
  missing <- setdiff(item$cols, names(item$data))
  if (length(missing)) stop(item$name, " is missing columns: ", paste(missing, collapse = ", "))
}

# Normalize identifiers and join only held-out test records.
raw <- raw |> mutate(transaction_id = as.character(transaction_id))
predictions <- predictions |> mutate(transaction_id = as.character(transaction_id))
if_scores <- if_scores |> mutate(transaction_id = as.character(transaction_id))
transactions <- raw |>
  inner_join(predictions, by = c("transaction_id", "is_fraud" = "actual")) |>
  left_join(if_scores |> select(transaction_id, anomaly_score), by = "transaction_id")

if (nrow(transactions) != nrow(predictions)) {
  stop("Transaction, prediction, and anomaly-score files do not align. Rerun scripts 01 and 04.")
}
if (!"amount" %in% names(transactions)) stop("Source transactions must include amount.")
if (!"merchant_category" %in% names(transactions)) stop("Source transactions must include merchant_category.")
if (!"geography" %in% names(transactions)) stop("Source transactions must include geography.")
if (!"time_of_day" %in% names(transactions)) stop("Source transactions must include time_of_day.")

PAL <- list(red = "#c0392b", amber = "#d68910", green = "#238b57",
            blue = "#2874a6", navy = "#243447", grey = "#657786")

fmt_pct <- function(x, digits = 1) ifelse(is.na(x), "N/A", percent(x, accuracy = 10^(-digits)))
fmt_num <- function(x) comma(x, accuracy = 1)
fmt_money <- function(x) dollar(x, accuracy = 1)

# Cost policies and threshold policies share the same strategy names.
policy_test <- if_policy |> filter(split == "test")
if (!"target_validation_alert_rate" %in% names(policy_test)) {
  policy_test$target_validation_alert_rate <- NA_real_
}
costs <- costs |> mutate(strategy = as.character(strategy))
policy_test <- policy_test |> mutate(strategy = as.character(strategy))

ui <- page_navbar(
  title = "FraudDetect | Risk Analytics",
  theme = bs_theme(bootswatch = "flatly", primary = PAL$navy),
  header = tags$div(
    class = "container-fluid",
    tags$style(HTML("
      .financial-kpi-row { display: grid !important;
        grid-template-columns: minmax(0, 5fr) minmax(0, 3fr) minmax(0, 4fr);
        gap: 1rem; align-items: stretch; margin-bottom: 1rem;
        width: 100%; }
      .financial-kpi-card { min-height: 155px !important;
        height: 155px !important; box-sizing: border-box; padding: 1rem;
        border: 1px solid #d9dee3; border-radius: .5rem; background: #fff;
        display: flex; flex-direction: column; justify-content: flex-start;
        gap: .65rem; overflow: visible; }
      .financial-kpi-card .shiny-input-container {
        display: block !important; width: 100% !important; min-height: 74px;
        flex: 0 0 auto; }
      .financial-kpi-card input.form-control {
        display: block !important; width: 100% !important; min-height: 38px;
        visibility: visible !important; opacity: 1 !important; }
      .financial-kpi-title { font-size: .95rem; font-weight: 600; color: #344054; }
      .financial-kpi-value { display: block; font-size: clamp(1.35rem, 1.8vw, 1.8rem);
        line-height: 1.25; font-weight: 650; overflow-wrap: anywhere; color: #243447; }
      .financial-kpi-note { color: #657786; font-size: .84rem; line-height: 1.35; margin: 0; }
      .financial-kpi-card .form-group { margin-bottom: 0; }
      .financial-kpi-card .form-control { max-width: 100%; }
      #sensitivity_table table, #assumptions_table table { width: 100%;
        table-layout: fixed; margin-bottom: 0; }
      #sensitivity_table th, #sensitivity_table td,
      #assumptions_table th, #assumptions_table td {
        white-space: normal; overflow-wrap: anywhere; vertical-align: middle;
        padding: .55rem .65rem; }
      #sensitivity_table th:nth-child(1) { width: 16%; }
      #sensitivity_table th:nth-child(2) { width: 15%; }
      #sensitivity_table th:nth-child(3) { width: 29%; }
      #sensitivity_table th:nth-child(4) { width: 12%; }
      #sensitivity_table th:nth-child(5) { width: 28%; }
      #assumptions_table th:first-child, #assumptions_table td:first-child { width: 62%; }
      .financial-note { line-height: 1.45; margin-top: .75rem; }
      #cost_plot { display: block; width: 100%; min-height: 520px; }
      #cost_plot .shiny-plot-output { min-height: 520px; }
      .card:has(#cost_plot) { overflow: visible; }
    ")),
    tags$p("Corrected R pipeline | Held-out test evaluation | Simulated transaction data",
           class = "text-muted small mb-2")
  ),

  nav_panel("Executive Overview",
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      value_box("Held-out transactions", fmt_num(nrow(transactions)),
                showcase = bsicons::bs_icon("credit-card"), theme = "primary"),
      value_box("Fraud prevalence", fmt_pct(mean(transactions$is_fraud)),
                showcase = bsicons::bs_icon("exclamation-triangle"), theme = "danger"),
      value_box("XGBoost test PR-AUC",
                fmt_num(model_metrics$test_pr_auc[model_metrics$model == "XGBoost"][1]),
                showcase = bsicons::bs_icon("graph-up"), theme = "success"),
      value_box("Investigation capacity", textOutput("overview_capacity", inline = TRUE),
                showcase = bsicons::bs_icon("people"), theme = "warning")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Fraud prevalence by merchant category"),
           plotOutput("overview_category", height = 320)),
      card(card_header("XGBoost score distribution by actual outcome"),
           plotOutput("overview_scores", height = 320))
    ),
    card(
      card_header("How to interpret this dashboard"),
      p("Model metrics are calculated on a held-out test set. Anomaly thresholds are selected using validation data. Financial impact is illustrative: transaction amount is an exposure proxy, not observed realized loss."),
      p("The investigation-capacity control is applied to the policy comparison and financial-impact views. It does not retrain models or alter test predictions.")
    )
  ),

  nav_panel("Fraud Patterns",
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Fraud rate by merchant category"),
           plotOutput("pattern_category", height = 330)),
      card(card_header("Fraud rate by time of day"),
           plotOutput("pattern_time", height = 330))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header("Fraud rate by geography"),
           plotOutput("pattern_geo", height = 300)),
      card(card_header("Transaction amount distribution"),
           plotOutput("pattern_amount", height = 300))
    )
  ),

  nav_panel("Predictive Modeling",
    layout_columns(
      col_widths = c(5, 7),
      card(card_header("Held-out model comparison"),
           plotOutput("model_auc", height = 300),
           p(class = "text-muted small",
             "ROC-AUC and PR-AUC are shown separately. PR-AUC is particularly informative when fraud is uncommon.")),
      card(card_header("Model performance metrics"),
           DTOutput("model_table"))
    ),
    card(card_header("Random Forest permutation importance"),
         plotOutput("feature_importance", height = 380))
  ),

  nav_panel("Anomaly Policies",
    card(
      card_header("Compare anomaly and combined alert strategies"),
      p("Isolation Forest is fitted on training features only. Alert cutoffs are derived from validation-score quantiles and evaluated on the held-out test set."),
      plotOutput("policy_tradeoff", height = 360),
      DTOutput("policy_table")
    )
  ),

  nav_panel("Financial Impact",
    div(class = "financial-kpi-row",
      div(class = "financial-kpi-card",
        div(class = "financial-kpi-title", "Investigation capacity"),
        numericInput("capacity", "Maximum alerts",
                     value = 500, min = 1, max = nrow(transactions),
                     step = 25, width = "100%"),
        p(class = "financial-kpi-note",
          "Policies above this alert limit are excluded.")
      ),
      div(class = "financial-kpi-card",
        div(class = "financial-kpi-title", "Review cost per alert"),
        div(class = "financial-kpi-value",
            fmt_money(as.numeric(assumptions$value[assumptions$assumption == "cost_per_alert_review"][1]))),
        p(class = "financial-kpi-note", "Illustrative investigation cost.")
      ),
      div(class = "financial-kpi-card",
        div(class = "financial-kpi-title", "Recovery assumption"),
        div(class = "financial-kpi-value",
            fmt_pct(as.numeric(assumptions$value[assumptions$assumption == "recovery_share_when_detected"][1]))),
        p(class = "financial-kpi-note",
          "Assumed share of detected fraud exposure prevented or recovered.")
      )
    ),
    card(
      card_header("Lowest estimated-cost policies within capacity"),
      plotOutput("cost_plot", height = 520),
      DTOutput("cost_table")
    ),
    card(
      card_header("Sensitivity analysis"),
      p(class = "text-muted small",
        "Lowest estimated-cost policy for each review-cost and recovery scenario, after applying the investigation-capacity limit."),
      tableOutput("sensitivity_table")
    ),
    card(
      card_header("Modeling assumptions and limitations"),
      tableOutput("assumptions_table"),
      p(class = "text-muted small financial-note",
        "These are scenario estimates, not measured bank losses, actual recoveries, or verified operational costs. Transaction amount is used as a proxy for fraud exposure. Validate assumptions with institution-specific data before operational use.")
    )
  ),

  nav_panel("Transaction Explorer",
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      selectInput("filter_category", "Merchant category",
                  choices = c("All", sort(unique(transactions$merchant_category)))),
      selectInput("filter_geo", "Geography",
                  choices = c("All", sort(unique(transactions$geography)))),
      selectInput("filter_label", "Actual outcome",
                  choices = c("All", "Fraud", "Legitimate")),
      selectInput("filter_alert", "XGBoost alert",
                  choices = c("All", "Alert", "No alert"))
    ),
    card(card_header("Held-out test transactions"),
         DTOutput("transaction_table"))
  )
)

server <- function(input, output, session) {
  output$overview_capacity <- renderText(fmt_num(if (is.null(input$capacity)) 500 else input$capacity))

  fraud_rates <- function(data, group) {
    data |>
      group_by(.data[[group]]) |>
      summarise(n = n(), fraud_rate = mean(is_fraud) * 100, .groups = "drop") |>
      arrange(desc(fraud_rate))
  }

  output$overview_category <- renderPlot({
    fraud_rates(transactions, "merchant_category") |>
      ggplot(aes(x = reorder(merchant_category, fraud_rate), y = fraud_rate)) +
      geom_col(fill = PAL$red) + coord_flip() +
      labs(x = NULL, y = "Fraud rate (%)") + theme_minimal(base_size = 12)
  })

  output$overview_scores <- renderPlot({
    transactions |>
      mutate(outcome = if_else(is_fraud == 1, "Fraud", "Legitimate")) |>
      ggplot(aes(x = xgboost_probability, fill = outcome)) +
      geom_histogram(bins = 35, position = "identity", alpha = 0.6) +
      scale_fill_manual(values = c("Legitimate" = PAL$blue, "Fraud" = PAL$red)) +
      labs(x = "XGBoost predicted probability", y = "Transactions", fill = NULL) +
      theme_minimal(base_size = 12)
  })

  output$pattern_category <- renderPlot({
    fraud_rates(transactions, "merchant_category") |>
      ggplot(aes(x = reorder(merchant_category, fraud_rate), y = fraud_rate)) +
      geom_col(fill = PAL$red) + coord_flip() +
      labs(x = NULL, y = "Fraud rate (%)") + theme_minimal()
  })
  output$pattern_time <- renderPlot({
    fraud_rates(transactions, "time_of_day") |>
      ggplot(aes(x = reorder(time_of_day, fraud_rate), y = fraud_rate)) +
      geom_col(fill = PAL$amber) +
      labs(x = NULL, y = "Fraud rate (%)") + theme_minimal()
  })
  output$pattern_geo <- renderPlot({
    fraud_rates(transactions, "geography") |>
      ggplot(aes(x = reorder(geography, fraud_rate), y = fraud_rate)) +
      geom_col(fill = PAL$blue) + coord_flip() +
      labs(x = NULL, y = "Fraud rate (%)") + theme_minimal()
  })
  output$pattern_amount <- renderPlot({
    ggplot(transactions, aes(x = amount, fill = factor(is_fraud,
            levels = c(0, 1), labels = c("Legitimate", "Fraud")))) +
      geom_histogram(bins = 40, position = "identity", alpha = 0.6) +
      scale_x_log10(labels = label_dollar()) +
      scale_fill_manual(values = c("Legitimate" = PAL$blue, "Fraud" = PAL$red)) +
      labs(x = "Transaction amount (log scale)", y = "Transactions", fill = NULL) +
      theme_minimal()
  })

  output$model_auc <- renderPlot({
    model_metrics |>
      select(model, test_roc_auc, test_pr_auc) |>
      pivot_longer(-model, names_to = "metric", values_to = "value") |>
      mutate(metric = recode(metric, test_roc_auc = "ROC-AUC", test_pr_auc = "PR-AUC")) |>
      ggplot(aes(x = reorder(model, value), y = value, fill = metric)) +
      geom_col(position = "dodge") + coord_flip() +
      scale_fill_manual(values = c("ROC-AUC" = PAL$blue, "PR-AUC" = PAL$amber)) +
      labs(x = NULL, y = "Score", fill = NULL) + theme_minimal()
  })
  output$model_table <- renderDT({
    datatable(model_metrics, rownames = FALSE, options = list(pageLength = 5, dom = "tip")) |>
      formatPercentage(c("precision", "recall", "specificity", "false_positive_rate",
                         "test_fraud_prevalence"), digits = 1)
  })

  importance_path <- file.path(out_dir, "rf_variable_importance.csv")
  importance <- if (file.exists(importance_path)) {
    readr::read_csv(importance_path, show_col_types = FALSE)
  } else {
    tibble(feature = character(), permutation_importance = double())
  }
  output$feature_importance <- renderPlot({
    validate(need(nrow(importance) > 0, "Run 01_modeling.R to generate RF variable importance."))
    importance |>
      slice_max(permutation_importance, n = 15) |>
      ggplot(aes(x = reorder(feature, permutation_importance),
                 y = permutation_importance)) +
      geom_col(fill = PAL$blue) + coord_flip() +
      labs(x = NULL, y = "Permutation importance") + theme_minimal()
  })

  output$policy_tradeoff <- renderPlot({
    policy_test |>
      mutate(strategy = str_replace_all(strategy, "_", " ")) |>
      ggplot(aes(x = recall, y = precision, size = alerts, label = strategy)) +
      geom_point(alpha = 0.75, colour = PAL$blue) +
      scale_x_continuous(labels = label_percent()) +
      scale_y_continuous(labels = label_percent()) +
      labs(x = "Recall", y = "Precision", size = "Alerts") +
      theme_minimal()
  })
  output$policy_table <- renderDT({
    datatable(policy_test |>
      select(strategy, alerts, true_positives, false_positives,
             false_negatives, precision, recall, specificity),
      rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE)) |>
      formatPercentage(c("precision", "recall", "specificity"), digits = 1)
  })

  capacity <- reactive({
    cap <- input$capacity
    if (is.null(cap) || !is.finite(cap) || cap < 1) 500 else cap
  })
  feasible_costs <- reactive({
    costs |>
      filter(alerts <= capacity()) |>
      arrange(estimated_total_cost)
  })
  output$capacity_status <- renderText({
    paste0("Policies are eligible only when alerts are at or below ",
           fmt_num(capacity()), ".")
  })
  assumption_value <- function(key) {
    value <- assumptions$value[assumptions$assumption == key]
    if (length(value)) value[[1]] else "Not specified"
  }
  output$review_assumption <- renderText({
    paste0(fmt_money(as.numeric(assumption_value("cost_per_alert_review"))),
           " per alert")
  })
  output$recovery_assumption <- renderText({
    paste0(fmt_pct(as.numeric(assumption_value("recovery_share_when_detected"))),
           " assumed recovery")
  })
  output$cost_plot <- renderPlot({
    dat <- feasible_costs() |> slice_head(n = 8)
    validate(need(nrow(dat) > 0, "No policy meets this alert capacity. Increase capacity."))
    ggplot(dat, aes(x = reorder(str_replace_all(strategy, "_", " "),
                                estimated_total_cost),
                    y = estimated_total_cost)) +
      geom_col(fill = PAL$green, width = 0.68) +
      coord_flip(clip = "off") +
      scale_y_continuous(labels = label_dollar(),
                         expand = expansion(mult = c(0, 0.08))) +
      labs(x = NULL, y = "Estimated total cost") +
      theme_minimal(base_size = 12) +
      theme(
        axis.text.y = element_text(size = 10, lineheight = 1.05),
        axis.text.x = element_text(size = 9),
        axis.title.x = element_text(size = 10, margin = margin(t = 8)),
        panel.grid.major.y = element_blank(),
        plot.margin = margin(12, 24, 12, 12)
      )
  })
  output$cost_table <- renderDT({
    dat <- feasible_costs()
    validate(need(nrow(dat) > 0, "No policy meets this alert capacity."))
    datatable(dat |>
      select(strategy, alerts, true_positives, false_positives,
             false_negatives, total_alert_review_cost,
             estimated_missed_fraud_loss, estimated_total_cost),
      rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE)) |>
      formatCurrency(c("total_alert_review_cost", "estimated_missed_fraud_loss",
                      "estimated_total_cost"), currency = "$")
  })

  output$sensitivity_table <- renderTable({
    # Apply the capacity constraint before selecting the lowest-cost policy.
    if (!"alerts" %in% names(sensitivity)) {
      return(data.frame(Note = "Sensitivity output lacks alert counts."))
    }
    best <- sensitivity |>
      filter(alerts <= capacity()) |>
      group_by(review_cost_per_alert, recovery_share_when_detected) |>
      slice_min(estimated_total_cost, n = 1, with_ties = FALSE) |>
      ungroup() |>
      arrange(review_cost_per_alert, recovery_share_when_detected) |>
      transmute(
        `Review cost` = dollar(review_cost_per_alert, accuracy = 1),
        `Recovery assumption` = percent(recovery_share_when_detected, accuracy = 1),
        `Selected policy` = str_replace_all(strategy, "_", " "),
        `Alerts` = comma(alerts),
        `Estimated total cost` = dollar(estimated_total_cost, accuracy = 1)
      )
    if (nrow(best) == 0) {
      return(data.frame(Note = "No policy meets the current investigation capacity. Increase the capacity to view scenario results."))
    }
    best
  }, striped = TRUE, bordered = FALSE, hover = TRUE,
  spacing = "s", rownames = FALSE, width = "100%")

  output$assumptions_table <- renderTable({
    assumptions |>
      transmute(
        Assumption = str_replace_all(assumption, "_", " "),
        Value = as.character(value)
      )
  }, striped = TRUE, bordered = FALSE, hover = TRUE,
  spacing = "s", rownames = FALSE, width = "100%")


  filtered_transactions <- reactive({
    dat <- transactions
    if (!is.null(input$filter_category) && input$filter_category != "All")
      dat <- dat |> filter(merchant_category == input$filter_category)
    if (!is.null(input$filter_geo) && input$filter_geo != "All")
      dat <- dat |> filter(geography == input$filter_geo)
    if (!is.null(input$filter_label) && input$filter_label != "All")
      dat <- dat |> filter(is_fraud == if_else(input$filter_label == "Fraud", 1L, 0L))
    if (!is.null(input$filter_alert) && input$filter_alert != "All")
      dat <- dat |> filter(xgboost_predicted == if_else(input$filter_alert == "Alert", 1L, 0L))
    dat |>
      transmute(transaction_id, merchant_category, amount, geography, time_of_day,
                xgboost_probability, xgboost_predicted, anomaly_score,
                is_fraud) |>
      arrange(desc(xgboost_probability))
  })
  output$transaction_table <- renderDT({
    datatable(filtered_transactions(), rownames = FALSE,
              filter = "top", options = list(pageLength = 15, scrollX = TRUE)) |>
      formatPercentage("xgboost_probability", digits = 1) |>
      formatStyle("is_fraud",
        target = "row",
        backgroundColor = styleEqual(c(0, 1), c("white", "#fde8e8")))
  })
}

shinyApp(ui, server)
