source("R/methods_config.R")
source("R/config.R")
source("R/marker_gene.R")
source("R/utils.R")
run_assign_methods <- function(method,train_data, test_data,exp_config){
  switch(method,
         scmap_cluster = assign.scmap_cluster(train_data, test_data),
         scmap_cell = assign.scmap_cell(train_data, test_data),
         chetah = assign.chetah(train_data, test_data),
         cellassign = assign.cellassign(train_data,exp_config),
         garnett = assign.garnett(train_data,test_data,exp_config),
         singlecellnet = assign.singlecellnet(train_data,test_data),
         stop("No such assigning method")
  )
  
}

run_cluster_methods <- function(method,data){
  switch(method,
         sc3 = cluster.sc3(data),
         liger = cluster.liger(data),
         seurat = cluster.seurat(data),
         cidr = cluster.cidr(data),
         tscan = cluster.tscan(data),
         stop("No such cluster method")
  )
}


####assigning using scmap cluster
assign.scmap_cluster <- function(train_data, test_data){
  require(scmap)
  require(scater)
  stopifnot(is(train_data,"SingleCellExperiment"))
  stopifnot(is(test_data,"SingleCellExperiment"))
  train_data <- logNormCounts(train_data)
  rowData(train_data)$feature_symbol <- rownames(train_data)
  train_data <- selectFeatures(train_data,n_features=methods.config.scmap[['nfeatures']]) %>%
    indexCluster(cluster_col = "label")
  test_data <- logNormCounts(test_data)
  rowData(test_data)$feature_symbol <- rownames(test_data)
  results <- scmapCluster(projection=test_data, index_list=list(metadata(train_data)$scmap_cluster_index))
  results$combined_labs
}

####assigning using scmap cell
assign.scmap_cell <- function(train_data, test_data){
  require(scmap)
  require(scater)
  stopifnot(is(train_data,"SingleCellExperiment"))
  stopifnot(is(test_data,"SingleCellExperiment"))
  train_data <- logNormCounts(train_data)
  rowData(train_data)$feature_symbol <- rownames(train_data)
  if(purrr::is_null(methods.config.scmap[['seed']]))
    set.seed(1)
  else
    set.seed(methods.config.scmap[['seed']])
  train_data <- selectFeatures(train_data,n_features=methods.config.scmap[['nfeatures']]) %>%
    indexCell()
  test_data <- logNormCounts(test_data)
  rowData(test_data)$feature_symbol <- rownames(test_data)
  cell_results <- scmapCell(projection=test_data, index_list = list(metadata(train_data)$scmap_cell_index))
  clusters_results <- scmapCell2Cluster(
    cell_results, 
    list(
      as.character(colData(train_data)$label)
    ),threshold = methods.config.scmap[['threshold']]
  )
  clusters_results$combined_labs
}

###assigning using chetah
assign.chetah <- function(train_data, test_data){
    require(SingleCellExperiment)
    require(CHETAH)
    stopifnot(is(train_data,"SingleCellExperiment"))
    stopifnot(is(test_data,"SingleCellExperiment"))
    colData(train_data)$celltypes <- colData(train_data)$label
  
    #run classifier
    test_data <- CHETAHclassifier(input = test_data, ref_cells = train_data)
    
    ## Extract celltypes:
    #CHETAH generates generic names for the intermediate types: “Unassigned” for cells that are classified to the very first node, 
    #and “Node1”, “Node2”, etc for the additional nodes
    unname(test_data$celltype_CHETAH)
}


#######assigning using garnet
assign.garnett <- function(train_data,test_data,exp_config){
  require(garnett)
  require(monocle)
  require(SingleCellExperiment)
  require(org.Hs.eg.db)
  print("start method garnett")
  stopifnot(is(test_data,"SingleCellExperiment"))
  stopifnot(is(train_data,"SingleCellExperiment"))
  m_config <- methods.config.garnett
  study <- metadata(train_data)$study[[1]]
  gene_name_type <- m_config[[study]]$gene_name_type
  pretrained_classifier_name <- m_config[[study]]$pretrained_classifier

  if(is_null(pretrained_classifier_name)){
    marker_file_path <- m_config[[study]]$marker_file_path
    if(purrr::is_null(marker_file_path)||!file.exists(str_glue("{marker_home}/{marker_file_path}"))){
      print("Garnett marker file not exist, generating marker file...")
      if(purrr::is_null(marker_file_path))
        marker_file_path <- str_glue("Garnett_{study}_marker_{gene_name_type}.txt")
      marker_gene_file <- exp_config$marker_gene_file
      generated_marker_gene_file <- str_glue("{study}_markergene_{m_config[[study]]$marker_gene_method}")
      marker_gene_method <- m_config[[study]]$marker_gene_method
      markers_mat <- utils.check_marker_genes(train_data,marker_gene_file, generated_marker_gene_file,marker_gene_method,study) 
      assign.garnett.generate_marker_file(markers_mat,marker_file_path,gene_name_type)
    }
    
    
    cds_train <- assign.garnett.process_data(train_data, gene_name_type)
    set.seed(260)
    classifier <- train_cell_classifier(cds = cds_train,
                                             marker_file = str_glue("{marker_home}/{marker_file_path}"),
                                             db=org.Hs.eg.db,
                                             cds_gene_id_type = gene_name_type,
                                             num_unknown = 50,
                                             marker_file_gene_id_type = gene_name_type)
    write_rds(classifier,str_glue("{pretrained_classifier_home}/pretrained_{study}_{gene_name_type}_classifier.rds"))
  }else{
    classifier_path <- str_glue("{pretrained_classifier_home}/{pretrained_classifier_name}")
    classifier <- readRDS(classifier_path)
  }
  cds_test <- assign.garnett.process_data(test_data, gene_name_type)
  
  cds_test <- classify_cells(cds_test, classifier,
                             db = org.Hs.eg.db,
                             cluster_extend = TRUE,
                             cds_gene_id_type = gene_name_type)
  unlist(list(pData(cds_test)$cell_type))
}


assign.garnett.process_data <- function(data, gene_name_type){
  mat <- counts(data)
  if(gene_name_type=="SYMBOL"){
    geneData <- as.tibble(rowData(data))
    geneData$fullGeneName <- rownames(data) 
    geneData <- dplyr::group_by(geneData,geneName) %>%
      dplyr::filter(count==max(count))
    mat <- counts(data[geneData$fullGeneName])
    rownames(mat) <- geneData$geneName
    geneData$gene_short_name <- geneData$geneName
    geneData <- as.data.frame(geneData)
    rownames(geneData) <- geneData$geneName
  }else if(gene_name_type=="ENSEMBL"){
    geneData <- rowData(data)
    mat <- counts(data)
    rownames(mat) <- geneData$EnsembleId
    geneData$gene_short_name <- geneData$geneName
    geneData <- as.data.frame(geneData)
    rownames(geneData) <- geneData$EnsembleId
  }else{
    stop(str_glue("Unknown gene name type: {gene_name_type}"))
  }
  
  
  cellData <- as.data.frame(colData(data))
  # create a new CDS object
  phenoData <- new("AnnotatedDataFrame", data = cellData)
  featureData <- new("AnnotatedDataFrame", data = geneData)
  cds <- newCellDataSet(as(mat, "dgCMatrix"),
                        phenoData = phenoData,
                        featureData = featureData)
  
  # generate size factors for normalization later
  cds <- estimateSizeFactors(cds)
}

assign.garnett.generate_marker_file <- function(markers_mat,marker_file_path,gene_name_type){

  if(gene_name_type == "SYMBOL"){
    gene_names <- rownames(markers_mat) %>%
                    purrr::map_chr(~{names <- str_split(.,"\\t")[[1]]
                                      return(names[which(!str_detect(names,"^ENSG0+"))])
                                      })
  }else{
    gene_names <- rownames(markers_mat) %>%
      purrr::map_chr(~{names <- str_split(.,"\\t")[[1]]
      return(names[which(str_detect(names,"^ENSG0+"))])
      })
  }
  rownames(markers_mat) <- gene_names
  cell_types <- colnames(markers_mat)
  marker_file_path <- str_glue("{marker_home}/{marker_file_path}")
  print(str_glue("Generating Garnett marker file: {marker_file_path}"))
  for(t in cell_types){
    line <- str_glue(">{t}")
    write(line,file=marker_file_path, append = TRUE)

    line <- str_c(names(markers_mat[which(markers_mat[,t] > 0),t]),collapse=", ")
    line <- str_c("expressed: ",line)
    write(line,file=marker_file_path,append = TRUE)
  }
}
  



###assigning using cellassign
assign.cellassign <- function(data,exp_config){
  require(tensorflow)
  require(cellassign)
  require(scran)
  stopifnot(is(data,"SingleCellExperiment"))
  m_config <- methods.config.cellassign
  marker_gene_file <- exp_config$marker_gene_file
  study <- metadata(data)$study[[1]]
  generated_marker_gene_file <- str_glue("{study}_markergene_{m_config$marker_gene_method}")
  marker_gene_method <- m_config$marker_gene_method
  markers_mat <- utils.check_marker_genes(marker_gene_file, generated_marker_gene_file,marker_gene_method,study) 
  counts(data) <- as.matrix(counts(data))
  data$celltypes <- colData(data)$label
  s <- computeSumFactors(data) %>% 
    sizeFactors()
  
  fit <- cellassign(exprs_obj = data[na.omit(matchidx),], 
                    marker_gene_info = markers_mat, 
                    s = s, 
                    learning_rate = m_config$learning_rate, 
                    shrinkage = m_config$shrinkage,
                    verbose = FALSE)
  fit$cell_type
}

######assigning using singlecellnet
assign.singlecellnet <- function(train_data, test_data){
  require(singleCellNet)
  stopifnot(is(train_data,"SingleCellExperiment"))
  stopifnot(is(test_data,"SingleCellExperiment"))
  #' extract sampTab and expDat sce object into regular S3 objects
  #' @param sce_object
  #' @param exp_type
  #' @param list
  #' @export
  extractSCE <- function(sce_object, exp_type = "counts"){
    #extract metadata
    sampTab = as.data.frame(colData(sce_object, internal = TRUE))
    sampTab$sample_name = rownames(sampTab)
    
    #extract expression matrix
    if(exp_type == "counts"){
      expDat = counts(sce_object)
    }
    
    if(exp_type == "normcounts"){
      expDat = normcounts(sce_object)
    }
    
    if(exp_type == "logcounts"){
      expDat = logcounts(sce_object)
    }
    
    return(list(sampTab = sampTab, expDat = expDat))
  }

  m_config <- methods.config.singlecellnet 
  set.seed(100) #can be any random seed number
  train_scefile <- extractSCE(train_data, exp_type = "counts") 
  train_metadata <- train_scefile$sampTab
  train_expdata <- train_scefile$expDat
  test_scefile <- extractSCE(test_data, exp_type = "counts") 
  test_metadata <- test_scefile$sampTab
  test_expdata <- test_scefile$expDat
  
  if(m_config$cross_species){
    common_gene_file <- str_glue("{data_home}{m_config$common_gene_file}")
    oTab <- utils_loadObject(fname = "../data/human_mouse_genes_Jul_24_2018.rda")
    aa <- csRenameOrth(expQuery = test_expdata, expTrain = train_expdata, orthTable = oTab)
    test_expdata <- aa[['expQuery']]
    train_expdata <- aa[['expTrain']]
  }else{
    commonGenes<-intersect(rownames(train_expdata), rownames(test_expdata))
    train_expdata <- train_expdata[commonGenes, ]
    test_expdata <- test_expdata[commonGenes, ]
  }
  ncells <- if(purrr::is_null(m_config$ncells)) 100 else m_config$ncells
  nTopGenes <- if(purrr::is_null(m_config$nTopGenes)) 10 else m_config$nTopGenes
  nRand <- if(purrr::is_null(m_config$nRand)) 70 else m_config$nRand
  nTrees <- if(purrr::is_null(m_config$nTrees)) 1000 else m_config$nTrees
  nTopGenePairs <- if(purrr::is_null(m_config$nTopGenePairs)) 25 else m_config$nTopGenePairs
  
  class_info<-scn_train(stTrain = train_metadata, expTrain = train_expdata, nTopGenes = nTopGenes, nRand = nRand, nTrees = nTrees, nTopGenePairs = nTopGenePairs, 
                        dLevel = "label", colName_samp = "sample_name")
  #predict
  pred_results <- scn_predict(cnProc=class_info[['cnProc']], expDat=test_expdata, nrand = 0)
  pred_labels <- assign_cate(classRes = pred_results, sampTab = test_metadata, cThresh = 0.5)
  pred_labels$category
}



### clustering using Seurat
cluster.seurat <- function(data) {
  require(Seurat)
  stopifnot(is(data,"SingleCellExperiment"))
  cnts <- counts(data)
  m_config <- methods.config.seurat
  ## PCA dimention redcution
  seuset <- CreateSeuratObject(cnts, project='simple_accuracy')
  seuset <- NormalizeData(object = seuset)
  seuset <- FindVariableFeatures(object = seuset,nfeatures = m_config[['nfeatures']])
  seuset <- ScaleData(object = seuset)
  seuset <- RunPCA(object = seuset)
  seuset <- FindNeighbors(object = seuset,dims = 1:m_config[['pc_dims']])
  seuset <- FindClusters(object = seuset, resolution = m_config[['resolution']])
  as.integer(unname(seuset$seurat_clusters))
}

### TSCAN
cluster.tscan <- function(data) {
  require(TSCAN)
  stopifnot(is(data,"SingleCellExperiment"))
  cnts <- counts(data)
  m_config <- methods.config.tscan
  procdata <- preprocess(as.matrix(cnts),cvcutoff=m_config[['cvcutoff']])
  if(!purrr::is_null(m_config[['k']]) )
    lpsmclust <- exprmclust(procdata, clusternum=m_config[['k']])
  else
    lpsmclust <- exprmclust(procdata)
  as.integer(unname(lpsmclust$clusterid))
}

### SC3
cluster.sc3 <- function(data) {
  require(SC3)
  stopifnot(is(data,"SingleCellExperiment"))
  counts(data) <- as.matrix(counts(data))
  data <- logNormCounts(data)
  m_config <- methods.config.sc3
  k <- m_config$k
  rowData(data)$feature_symbol <- rownames(data)
  data <- data[!duplicated(rowData(data)$feature_symbol),]
  data <- sc3_prepare(data)
  if(purrr::is_null(k)){
    data <- sc3_estimate_k(data)## estimate number of clusters
    k <- metadata(sce)$sc3$k_estimation
  }
  data <- sc3_calc_dists(data)
  data <- sc3_calc_transfs(data)
  data <- sc3_kmeans(data, ks = k)
  data <- sc3_calc_consens(data)
  col_data <- colData(data)
  colTb = as.vector(col_data[ , grep("sc3_", colnames(col_data))])
  as.integer(colTb)
}

#####liger
cluster.liger <- function(data){
  require(liger)
  m_config <- methods.config.liger
  stopifnot(is(data,"SingleCellExperiment"))
  data_list <- list(counts(data))
  names(data_list) <- metadata(data)$study[[1]]
  liger_data <- createLiger(data_list)
  liger_data <- normalize(liger_data)
  liger_data <- selectGenes(liger_data, var.thresh = c(0.3, 0.875), do.plot = F)
  liger_data <- scaleNotCenter(liger_data)
  ###suggestK(liger_data, num.cores = 5, gen.new = T, plot.log2 = F,nrep = 5)
  k.suggest <- if(purrr::is_null(m_config$k.suggest))  25 else m_config$k.suggest
  thresh <- if(purrr::is_null(m_config$thresh)) 5e-5 else m_config$thresh
  lambda <- if(purrr::is_null(m_config$lambda)) 5 else m_config$lambda
  resolution <- if(purrr::is_null(m_config$resolution)) 1.0 else m_config$resolution
  liger_data <- optimizeALS(liger_data, k=k.suggest, thresh = thresh, lambda=lambda,nrep = 3)
  liger_data <- quantileAlignSNF(liger_data,resolution = resolution) #SNF clustering and quantile alignment
  as.integer(unname(liger_data@clusters))
}







### Monocle
cluster.monocle <- function(counts, K) {
  require(monocle)
  dat <- newCellDataSet(counts)
  dat <- estimateSizeFactors(dat)
  dat <- estimateDispersions(dat)
  
  ## pick marker genes for cell clustering
  disp_table <- dispersionTable(dat)
  ix <- order(disp_table[,"mean_expression"], decreasing=TRUE)
  unsup_clustering_genes <- disp_table[ix[50:1000], "gene_id"]
  ## unsup_clustering_genes <- subset(disp_table, mean_expression >= 1)
  dat <- setOrderingFilter(dat, unsup_clustering_genes)
  ## the follwoing step can be slow. Need to keep marker genes number low.
  dat <- reduceDimension(dat, reduction_method="tSNE")
  
  ## clustering
  if( !missing(K) )
    dat <- clusterCells(dat, num_clusters = K)
  else
    dat <- clusterCells(dat)
  
  pData(dat)$Cluster
}

### CIDR
cluster.cidr <- function(counts, K) {
  require(cidr)
  sData <- scDataConstructor(counts)
  sData <- determineDropoutCandidates(sData)
  sData <- wThreshold(sData)
  sData <- scDissim(sData)
  sData <- scPCA(sData, plotPC=FALSE)
  sData <- nPC(sData)
  if(missing(K))
    sData <- scCluster(sData)
  else
    sData <- scCluster(sData, nCluster=K)
  
  return(sData@clusters)
}


