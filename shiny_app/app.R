
library("shiny")
library("shinythemes")
library("data.table")
library("wesanderson")
library("DT")
library("stringr")
library("ggplot2")
library("dplyr")
library("dbplyr")
library("RSQLite")
library("DBI")

###############
## Shiny App ##
###############

options(browser = "/bin/firefox")

## Load Data
## ----------

## Load markers, UMAP, cell meta-data, and gene counts.

markers <- fread(file.path("datasets", "markers.tsv"))
umap <- fread(file.path("datasets", "umap_embeddings.tsv"))
metadata <- fread(file.path("datasets", "meta_data.tsv"))

con <- dbConnect(SQLite(), "datasets/gene_counts.sqlite")
counts <- tbl(con, "counts")

## Making SQLite database for gene counts.

#counts <- fread(file.path("datasets", "gene_counts.tsv"))
#counts <- melt(
#  counts, id.vars = "cell_id", variable.name = "gene",
#  value.name = "exp"
#)

#con <- dbConnect(SQLite(), "datasets/gene_counts.sqlite")
#copy_to(con, counts, "counts", temporary = FALSE, indexes = list("gene"))
#dbDisconnect(con)

## Retrieve Counts

get_counts <- function(genes) {
  gene_counts <- counts %>%
    filter(gene %in% genes) %>%
    collect %>%
    as.data.table %>%
    dcast(cell_id ~ gene)
}

## Shiny App UI
## ----------

ui <- fluidPage(theme = shinytheme("yeti"), navbarPage(title = "Sam scRNA-seq",

## Meta-data Navigation page.
tabPanel("Meta-Data", tabsetPanel(

  ## Dimension Plots Tab.
  tabPanel("Dim Plot", sidebarLayout(
    # Sidebar.
    sidebarPanel(width = 2,
      checkboxGroupInput(
        "dim_samples", "Samples",
        selected = unique(metadata[["orig.ident"]]),
        choices = unique(metadata[["orig.ident"]])
      ),
      selectInput(
        "dim_color", "Color By", selected = "orig.ident",
        choices = c(
          "orig.ident", "nCount_SCT", "nFeature_SCT", "S.Score",
          "G2M.Score", "Phase", "custom_clusters", "percent.mt"
        )
      ),
      selectInput(
        "dim_palette", "Color Palette", selected = "default",
        choices = c("default", "viridis", "wesanderson")
      ),
      selectInput(
        "dim_split", "Split By", selected = "none",
        choices = c("none", "orig.ident", "Phase", "custom_clusters")
      ),
      numericInput("dim_cols", "Number of Columns", 2, 1, 10, 1),
      sliderInput("dim_pointsize", "Point Size", 0.25, 5, 0.75, 0.25),
      sliderInput("dim_fontsize", "Font Size", 1, 36, 18, 1),
      textInput("dim_file", "File Name", "dimplot.png"),
      fluidRow(
        column(6, numericInput("dim_height", "Height", 8, 1, 36, 0.5)),
        column(6, numericInput("dim_width", "Width", 12, 1, 36, 0.5))
      ),
      downloadButton("dim_save", "Download")
    ),
    # Main panel.
    mainPanel(width = 10, plotOutput("dim_plot", height = 750))
  ))
	
)),

## Marker Navigation page.
tabPanel("Markers", tabsetPanel(

  ## Table tab.
  tabPanel("Marker Table", sidebarLayout(
    # Sidebar.
    sidebarPanel(width = 2,
      checkboxGroupInput(
        "mtable_cluster", "Clusters",
        selected = unique(markers[["cluster"]]),
        choices = unique(markers[["cluster"]])
      ),
      fluidRow(
          column(6, numericInput("mtable_fc", "FC Cutoff", 1.5, 1.5, 10, 0.5)),
          column(6, numericInput("mtable_fdr", "FDR Cutoff", 0.05, 0.005, 0.05, 0.005))
      )
    ),
    # Main panel.
    mainPanel(width = 10, dataTableOutput("mtable_table"))
  ))

)),

## Expression Navigation page.
tabPanel("Expression", tabsetPanel(

  ## Dim Plot tab.
  tabPanel("Dim Plot", sidebarLayout(
    # Sidebar.
    sidebarPanel(width = 2,
      checkboxGroupInput(
        "expdim_samples", "Samples",
        selected = unique(metadata[["orig.ident"]]),
        choices = unique(metadata[["orig.ident"]])
      ),
      textInput("expdim_gene", "Gene", "KDM1A"),
      selectInput("expdim_split", "Split By", c("none", "sample", "cluster"), "none"),
      numericInput("expdim_cols", "Number of Columns", 2, 1, 10, 1),
      selectInput(
        "expdim_palette", "Color Palette", selected = "default",
        choices = c("darkblue", "darkgreen", "darkred", "viridis", "wesanderson")
      ),
      sliderInput("expdim_pointsize", "Point Size", 0.25, 5, 0.75, 0.25),
      sliderInput("expdim_fontsize", "Font Size", 1, 36, 18, 1),
      textInput("expdim_file", "File Name", "dimplot.png"),
      fluidRow(
        column(6, numericInput("expdim_height", "Height", 8, 1, 36, 0.5)),
        column(6, numericInput("expdim_width", "Width", 12, 1, 36, 0.5))
      ),
      downloadButton("expdim_save", "Download")
    ),
    # Main panel
    mainPanel(width = 10, plotOutput("expdim_plot", height = 750))
  )),
  ## Expression Plot tab.
  tabPanel("Expression Plot", sidebarLayout(
    # Sidebar.
    sidebarPanel(width = 2,
      checkboxGroupInput(
        "exp_samples", "Samples",
        selected = unique(metadata[["orig.ident"]]),
        choices = unique(metadata[["orig.ident"]])
      ),
      textAreaInput("exp_genes", "Genes", "KDM1A", rows = 3),
      selectInput("exp_type", "Plot Type", c("violin", "box", "jitter"), "violin"),
      selectInput("exp_split", "Split By", c("none", "sample", "cluster")),
      numericInput("exp_cols", "Number of Columns", 2, 1, 10, 1),
      selectInput(
        "exp_palette", "Color Palette", selected = "default",
        choices = c("default", "viridis", "wesanderson")
      ),
      sliderInput("exp_fontsize", "Font Size", 1, 36, 18, 1)
    ),
    # Main panel.
    mainPanel(width = 10, plotOutput("exp_plot", height = 750))
  ))

))

))

## Shiny App Server
## ----------

server <- function(input, output) {

  ## Dimension Reduction.
  dim_plot <- reactive({

    # Select samples.
    meta_data <- metadata[orig.ident %in% input$dim_samples]

    # Add the UMAP reductions to the meta-data.
    meta_data <- merge(meta_data, umap, by = "cell_id")

    # Create the base plot.
    p <- ggplot(meta_data, aes(x = UMAP_1, y = UMAP_2)) +
      geom_point(aes_string(color = input$dim_color), size = input$dim_pointsize) +
      theme_minimal() +
      theme(
        text = element_text(size = input$dim_fontsize)
      )

    # Facet the plot if a split specified.
    if (input$dim_split != "none") {
        p <- p + facet_wrap(
          as.formula(str_c("~", input$dim_split)),
          ncol = input$dim_cols
        )
    }

    # Customize the color palette.
    if (input$dim_palette == "wesanderson") {
        if (is(meta_data[[input$dim_color]], "numeric")) {
          wes_colors <- wes_palette("Zissou1", 100, "continuous")
          p <- p + scale_color_gradientn(colors = wes_colors)
        } else {
          unique_values <- length(unique(meta_data[[input$dim_color]]))
          wes_colors <- wes_palette("Zissou1", unique_values, "continuous")
          p <- p + scale_color_manual(values = wes_colors)
        }
    } else if (input$dim_palette == "viridis") {
      if (is(meta_data[[input$dim_color]], "numeric")) {
        p <- p + scale_color_viridis_c()
      } else {
        p <- p + scale_color_viridis_d()
      }
    }

    return(p)

  })

  # Output the plot.
  output$dim_plot <- renderPlot({dim_plot()})

  # Save the plot.
  output$dim_save <- downloadHandler(
    filename = function() {input$dim_file},
    content = function(file) {
      ggsave(file, plot = dim_plot(), height = input$dim_height, width = input$dim_width)
    }
  )

  ## Markers.
  output$mtable_table <- renderDataTable({
    
    # Select clusters.
    marker_data <- markers[cluster %in% input$mtable_cluster]

    # Filter by FDR and log2FC.
    marker_data <- marker_data[
      abs(avg_log2FC) > log2(input$mtable_fc) &
      p_val_adj < input$mtable_fdr
    ]

    return(marker_data)

  },
    extensions = "Buttons",
    options = list(
      order = list(8, "desc"),
      dom = "Bfrtpli",
      buttons = c('copy', 'csv', 'excel', 'print')
    )
  )

  ## Gene expression dim plot.
  expdim_plot <- reactive({

    # Get the expression values for the gene.
    exp_data <- get_counts(input$expdim_gene)

    # Merge the gene expression back into the meta-data and UMAP.
    exp_data <- merge(metadata, exp_data, by = "cell_id")
    exp_data <- merge(exp_data, umap, by = "cell_id")

    # Keep only the selected samples.
    exp_data <- exp_data[orig.ident %in% input$expdim_samples]

    # Make a dim plot of expression.
    p <- ggplot(exp_data, aes(x = UMAP_1, y = UMAP_2)) +
      geom_point(
        aes_string(color = input$expdim_gene),
        size = input$expdim_pointsize
      ) +
      theme_minimal() +
      theme(text = element_text(size = input$expdim_fontsize))

    # Facet the plot if a split specified.
    if (input$expdim_split != "none") {
        if (input$expdim_split == "sample") {
          split_by <- "orig.ident"
        } else if (input$expdim_split == "cluster") {
          split_by <- "custom_clusters"
        }

        p <- p + facet_wrap(
          as.formula(str_c("~", split_by)),
          ncol = input$expdim_cols
        )
    }

    # Set proper colors.
    if (input$expdim_palette %in% c("darkblue", "darkred", "darkgreen")) {
      p <- p + scale_color_gradient(low = "#e6e6e6", high = input$expdim_palette)
    } else if (input$expdim_palette == "viridis") {
      p <- p + scale_color_viridis_c()
    } else if (input$expdim_palette == "wesanderson") {
      wes_colors <- wes_palette("Zissou1", 100, "continuous")
      p <- p + scale_color_gradientn(colors = wes_colors)
    }

    return(p)

  })

  # Plot the gene expression.
  output$expdim_plot <- renderPlot({expdim_plot()})

  # Save the plot.
  output$expdim_save <- downloadHandler(
    filename = function() {input$expdim_file},
    content = function(file) {
      ggsave(file, plot = expdim_plot(), height = input$expdim_height, width = input$expdim_width)
    }
  )

  ## Gene expression plots.
  exp_plot <- reactive({

    # Get the expression values for the genes.
    genes <- str_split(input$exp_genes, "\\s", simplify = TRUE)[1, ]
    exp_data <- get_counts(genes)

    # Merge the expression values back into the meta-data.
    exp_data <- merge(metadata, exp_data, by = "cell_id")
    exp_data <- melt(
      exp_data, measure.vars = genes, variable.name = "gene",
      value.name = "expression"
    )

    # Keep only the desired samples.
    exp_data <- exp_data[orig.ident %in% input$exp_samples]

    # Plot the expression data.
    if (input$exp_type == "jitter") {
      p <- ggplot(exp_data, aes(x = gene, y = expression, color = gene))
    } else if (input$exp_type == "box") {
      p <- ggplot(exp_data, aes(x = gene, y = expression, fill = gene))
    } else {
      p <- ggplot(exp_data, aes(x = gene, y = expression, fill = gene, color = gene))
    }

    p <- p +
      theme_minimal() +
      theme(text = element_text(size = input$exp_fontsize))

    # Create the proper plot type.
    if (input$exp_type == "violin") {
      p <- p + geom_violin()
    } else if (input$exp_type == "box") {
      p <- p + geom_boxplot()
    } else if (input$exp_type == "jitter") {
      p <- p + geom_jitter()
    }

    # Split the plot.
    if (input$exp_split != "none") {
        if (input$exp_split == "sample") {
          split_by <- "orig.ident"
        } else if (input$exp_split == "cluster") {
          split_by <- "custom_clusters"
        }

        p <- p + facet_wrap(
          as.formula(str_c("~", split_by)),
          ncol = input$exp_cols
        )
    }

    # Set the proper color.
    if (input$exp_palette == "wesanderson") {
      wes_colors <- wes_palette("Zissou1", length(genes), "continuous")
      if (input$exp_type == "jitter") {
        p <- p + scale_color_manual(values = wes_colors)
      } else if (input$exp_type == "box") {
        p <- p + scale_fill_manual(values = wes_colors)
      } else {
        p <- p +
          scale_fill_manual(values = wes_colors) +
          scale_color_manual(values = wes_colors)
      }
    } else if (input$exp_palette == "viridis") {
      if (input$exp_type == "jitter") {
        p <- p + scale_color_viridis_d()
      } else if (input$exp_type == "box") {
        p <- p + scale_fill_viridis_d()
      } else {
        p <- p +
          scale_fill_viridis_d() +
          scale_color_viridis_d()
      }
    }

    return(p)

  })

  output$exp_plot <- renderPlot({exp_plot()})

}

## Run the Shiny App
## ----------

shinyApp(ui = ui, server = server)
