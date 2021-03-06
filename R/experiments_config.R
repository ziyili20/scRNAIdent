source('R/config.R')
source('R/dataset_config.R')
experiments.cluster.data <- list(simple_accuracy=datasets$PBMC, cell_number=datasets$PBMC, sequencing_depth=datasets$PBMC,
                         cell_types=datasets$PBMC,batch_effects_no_free=datasets$pancreas)

experiments.assign.data <- list(
  train_dataset=list(simple_accuracy=datasets$PBMC, cell_number=datasets$PBMC, sequencing_depth=datasets$PBMC,
                     cell_types=datasets$PBMC),
  test_dataset=list(simple_accuracy=datasets$PBMC, cell_number=datasets$PBMC, sequencing_depth=datasets$PBMC,
                    cell_types=datasets$PBMC)
  )
  
experiments.methods <- list(
  simple_accuracy=list(cluster=c('seurat','tscan','sc3','liger'),assign=c('scmap_cluster','scmap_cell','chetah','singlecellnet','garnett'),marker_gene_assign=c("cellassign")), 
  cell_number=list(cluster=c('seurat','tscan','sc3','liger'),assign=c('scmap_cluster','scmap_cell','chetah','singlecellnet'),marker_gene_assign=c("cellassign")),
  sequencing_depth=list(cluster=c('seurat','tscan','sc3','liger'),assign=c('scmap_cluster','scmap_cell','chetah','singlecellnet'),marker_gene_assign=c("cellassign")),
  cell_types=list(cluster=c('sc3','seurat','tscan','liger'),assign=c('scmap','chetah','garnet','cellassign','singlecellnet'),marker_gene_assign=c("cellassign")),
  batch_effects=list(cluster=c('seurat','tscan','sc3','liger'),assign=c('scmap_cluster','scmap_cell','chetah','singlecellnet'),marker_gene_assign=c(),
                     cluster_batch_free=c('seurat','tscan','sc3','liger'), assign_batch_free=c('chetah','singlecellnet'), marker_gene_assign_batch_free=c()
                     )
)

experiments.parameters <- list(
  simple_accuracy=list(sample_num=300, cv=TRUE, cv_fold=5,metrics=c('ARI','AMI','FMI'),
                       marker_gene_file=NULL),
  cell_number=list(sample_num=c(100,200,400),cv=TRUE,cv_fold=5,metrics=c('ARI','AMI','FMI'),
                   marker_gene_file=NULL),
  sequencing_depth=list(quantile=list(low=0.2,high=0.8),cv=TRUE,cv_fold=5,metrics=c('ARI','AMI','FMI'),
                        marker_gene_file=NULL),
  cell_types=list(),
  batch_effects=list(sample_num=NA,cv=FALSE,remove_batch=TRUE,metrics=c('ARI','AMI','FMI'),
                     marker_gene_file="pancreasMarkerGenes.csv")
)