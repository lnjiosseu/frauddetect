# =============================================================================
# FraudDetect: shiny/app.R — Interactive Risk Analytics Dashboard
# =============================================================================

# Clear environment
#rm(list = ls())

if (interactive()) {
  setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))
}

library(shiny)
library(bslib)
library(tidyverse)

# Load data (run scripts first to generate outputs/)
load_data <- function() {
  list(
    transactions  = read_csv("data/transactions_scored.csv",  show_col_types = FALSE),
    model_results = read_csv("outputs/model_results.csv",     show_col_types = FALSE),
    key_metrics   = read_csv("outputs/key_metrics.csv",       show_col_types = FALSE),
    fraud_by_cat  = read_csv("outputs/fraud_by_category.csv", show_col_types = FALSE),
    fraud_by_time = read_csv("outputs/fraud_by_time.csv",     show_col_types = FALSE),
    fraud_by_geo  = read_csv("outputs/fraud_by_geography.csv",show_col_types = FALSE),
    risk_tiers    = read_csv("outputs/risk_tier_summary.csv", show_col_types = FALSE),
    risk_segments = read_csv("outputs/risk_segments.csv",     show_col_types = FALSE),
    feat_imp      = read_csv("outputs/feature_importance.csv",show_col_types = FALSE),
    test_preds    = read_csv("outputs/test_predictions.csv",  show_col_types = FALSE)
  )
}

d <- load_data()

# Colour palette
PAL <- list(high = "#e74c3c", med = "#f39c12", low = "#27ae60",
            blue = "#2980b9", dark = "#2c3e50", light = "#ecf0f1")

ui <- page_navbar(
  title = "FraudDetect — Risk Analytics Dashboard",
  theme = bs_theme(bootswatch = "flatly", primary = PAL$dark),

  # ── Tab 1: Overview ────────────────────────────────────────────────────────
  nav_panel("Overview",
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      value_box("Total Transactions", scales::comma(nrow(d$transactions)),
                showcase = bsicons::bs_icon("credit-card"), theme = "primary"),
      value_box("Fraud Rate",
                paste0(round(mean(d$transactions$is_fraud) * 100, 2), "%"),
                showcase = bsicons::bs_icon("exclamation-triangle-fill"), theme = "danger"),
      value_box("High-Risk Transactions",
                scales::comma(sum(d$transactions$risk_tier == "High")),
                showcase = bsicons::bs_icon("shield-exclamation"), theme = "warning"),
      value_box("Anomalies Flagged",
                scales::comma(sum(d$transactions$anomaly_combined)),
                showcase = bsicons::bs_icon("bug-fill"), theme = "secondary")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Fraud Rate by Merchant Category"),
        plotOutput("plot_fraud_cat", height = "320px")
      ),
      card(
        card_header("Risk Score Distribution by Fraud Label"),
        plotOutput("plot_risk_dist", height = "320px")
      )
    )
  ),

  # ── Tab 2: Model Performance ────────────────────────────────────────────────
  nav_panel("Model Performance",
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Model Comparison — AUC-ROC"),
        plotOutput("plot_model_compare", height = "280px"),
        hr(),
        card_header("Key Metrics"),
        tableOutput("tbl_metrics")
      ),
      card(
        card_header("Feature Importance (Logistic Regression Coefficients)"),
        plotOutput("plot_feat_imp", height = "400px")
      )
    )
  ),

  # ── Tab 3: Risk Segmentation ─────────────────────────────────────────────
  nav_panel("Risk Segmentation",
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Fraud Rate by Time of Day"),
        plotOutput("plot_time", height = "280px")
      ),
      card(
        card_header("Fraud Rate by Geography"),
        plotOutput("plot_geo", height = "280px")
      )
    ),
    card(
      card_header("Risk Tier Breakdown"),
      tableOutput("tbl_risk_tiers")
    ),
    card(
      card_header("Top Risk Segments (Merchant × Geography × Time)"),
      tableOutput("tbl_segments")
    )
  ),

  # ── Tab 4: Transaction Explorer ─────────────────────────────────────────
  nav_panel("Transaction Explorer",
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      selectInput("sel_cat", "Merchant Category",
                  choices = c("All", unique(d$transactions$merchant_category))),
      selectInput("sel_geo", "Geography",
                  choices = c("All", unique(d$transactions$geography))),
      selectInput("sel_tier", "Risk Tier",
                  choices = c("All", "High", "Medium", "Low")),
      selectInput("sel_fraud", "Fraud Label",
                  choices = c("All", "Fraud" = "1", "Legitimate" = "0"))
    ),
    card(
      card_header("Filtered Transactions"),
      DT::dataTableOutput("tbl_transactions")
    )
  )
)

server <- function(input, output, session) {

  # Plot: fraud rate by category
  output$plot_fraud_cat <- renderPlot({
    d$fraud_by_cat %>%
      mutate(merchant_category = fct_reorder(merchant_category, fraud_rate)) %>%
      ggplot(aes(x = merchant_category, y = fraud_rate, fill = fraud_rate)) +
      geom_col() +
      coord_flip() +
      scale_fill_gradient(low = PAL$low, high = PAL$high) +
      labs(x = NULL, y = "Fraud Rate (%)", fill = NULL) +
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")
  })

  # Plot: risk score distribution
  output$plot_risk_dist <- renderPlot({
    d$transactions %>%
      mutate(Fraud = factor(is_fraud, labels = c("Legitimate", "Fraud"))) %>%
      ggplot(aes(x = risk_score, fill = Fraud)) +
      geom_histogram(bins = 40, alpha = 0.7, position = "identity") +
      scale_fill_manual(values = c(PAL$blue, PAL$high)) +
      labs(x = "Risk Score", y = "Count", fill = NULL) +
      theme_minimal(base_size = 13)
  })

  # Plot: model comparison
  output$plot_model_compare <- renderPlot({
    d$model_results %>%
      mutate(model = fct_reorder(model, auc_roc)) %>%
      ggplot(aes(x = model, y = auc_roc, fill = model)) +
      geom_col(width = 0.5) +
      geom_text(aes(label = sprintf("%.4f", auc_roc)), hjust = -0.1, size = 4) +
      coord_flip(ylim = c(0.7, 1.0)) +
      scale_fill_manual(values = c(PAL$blue, PAL$med, PAL$high)) +
      labs(x = NULL, y = "AUC-ROC") +
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")
  })

  # Table: key metrics
  output$tbl_metrics <- renderTable({
    d$key_metrics
  }, striped = TRUE, hover = TRUE)

  # Plot: feature importance
  output$plot_feat_imp <- renderPlot({
    d$feat_imp %>%
      mutate(feature = fct_reorder(feature, abs(coefficient)),
             direction = ifelse(coefficient > 0, "Increases Risk", "Decreases Risk")) %>%
      ggplot(aes(x = feature, y = coefficient, fill = direction)) +
      geom_col() +
      coord_flip() +
      scale_fill_manual(values = c("Increases Risk" = PAL$high,
                                   "Decreases Risk" = PAL$blue)) +
      labs(x = NULL, y = "Log-Odds Coefficient", fill = NULL) +
      theme_minimal(base_size = 13)
  })

  # Plot: time of day
  output$plot_time <- renderPlot({
    d$fraud_by_time %>%
      mutate(time_of_day = fct_reorder(time_of_day, fraud_rate)) %>%
      ggplot(aes(x = time_of_day, y = fraud_rate, fill = fraud_rate)) +
      geom_col() +
      scale_fill_gradient(low = PAL$low, high = PAL$high) +
      labs(x = NULL, y = "Fraud Rate (%)") +
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")
  })

  # Plot: geography
  output$plot_geo <- renderPlot({
    d$fraud_by_geo %>%
      ggplot(aes(x = geography, y = fraud_rate, fill = geography)) +
      geom_col(width = 0.4) +
      scale_fill_manual(values = c(PAL$blue, PAL$high)) +
      labs(x = NULL, y = "Fraud Rate (%)") +
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")
  })

  # Table: risk tiers
  output$tbl_risk_tiers <- renderTable({
    d$risk_tiers
  }, striped = TRUE, hover = TRUE)

  # Table: top segments
  output$tbl_segments <- renderTable({
    head(d$risk_segments, 20)
  }, striped = TRUE, hover = TRUE)

  # Reactive filter for transaction explorer
  filtered_txns <- reactive({
    df <- d$transactions
    if (input$sel_cat   != "All") df <- df %>% filter(merchant_category == input$sel_cat)
    if (input$sel_geo   != "All") df <- df %>% filter(geography == input$sel_geo)
    if (input$sel_tier  != "All") df <- df %>% filter(risk_tier == input$sel_tier)
    if (input$sel_fraud != "All") df <- df %>% filter(is_fraud == as.integer(input$sel_fraud))
    df %>%
      select(transaction_id, merchant_category, amount, geography,
             time_of_day, risk_score, risk_tier, is_fraud,
             anomaly_combined, isolation_score) %>%
      arrange(desc(risk_score))
  })

  output$tbl_transactions <- DT::renderDataTable({
    DT::datatable(filtered_txns(), options = list(pageLength = 15), rownames = FALSE) %>%
      DT::formatStyle("is_fraud",
                      backgroundColor = DT::styleEqual(c(0, 1), c("white", "#fde8e8"))) %>%
      DT::formatStyle("risk_tier",
                      color = DT::styleEqual(c("Low", "Medium", "High"),
                                             c(PAL$low, PAL$med, PAL$high)))
  })
}

shinyApp(ui, server)
