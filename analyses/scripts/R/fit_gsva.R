
library("GSVA")
library("jsonlite")
library("rhdf5")
library("optparse")
library("nipals")
source("scripts/R/script_util.R")


###########################
# PARSE ARGUMENTS
option_list <- list(
    make_option("--omic_type", type="character", default="mrnaseq", help="The type of omic data to use. Default 'mrnaseq'."),
    make_option("--kcdf", type="character", default="Gaussian", help="'Gaussian' or 'Poisson'."),
    make_option("--minsize", default=10, help="Minimum gene set size. Default 10."),
    make_option("--maxsize", default=500, help="Maximum gene set size. Default 100."),
    make_option("--threads", default=4, help="Number of CPU threads to use. Default 1."),
    make_option("--var_filter", type="double", default=0.05, help="The top fraction of features to keep, ranked by variance")
    )

parser <- OptionParser(usage="fit_gsva.R DATA_HDF PATHWAY_JSON TRANSFORMED_HDF FITTED_MODEL_RDS [OPTS]",
                       option_list=option_list)

print("PARSING ARGS")

arguments <- parse_args(parser, positional_arguments=4)

opts <- arguments$options
omic_type <- opts$omic_type
kcdf <- opts$kcdf
minsize <- opts$minsize
maxsize <- opts$maxsize
threads <- opts$threads
var_filter <- opts$var_filter

pargs <- arguments$args
data_hdf <- pargs[1]
pwy_json <- pargs[2]
fitted_model_rds <- pargs[3]
transformed_hdf <- pargs[4]

####################################
# LOAD PATHWAYS

print("LOADING PATHWAYS")
pwy_dict <- read_json(pwy_json)
pwys <- pwy_dict$pathways
pwy_names <- pwy_dict$names

print("TRANSLATING TO GENESETS")
# translate to genesets
genesets <- pwys_to_genesets(pwys, pwy_names)


###################################
# LOAD RNASEQ DATA

print("LOADING OMIC DATA")
omic_data <- h5read(data_hdf, "omic_data/data")
feature_genes <- h5read(data_hdf, "omic_data/feature_genes")
feature_assays <- h5read(data_hdf, "omic_data/feature_assays")
instances <- h5read(data_hdf, "omic_data/instances")
instance_groups <- h5read(data_hdf, "omic_data/instance_groups")


#######################################
# FILTER THE FEATURES 

# Filter by omic type
relevant_cols <- (feature_assays == omic_type)
omic_data <- omic_data[,relevant_cols]
feature_genes <- feature_genes[relevant_cols]
rownames(omic_data) <- instances
colnames(omic_data) <- feature_genes

# Filter features by NaNs 
omic_data <- omic_data[,colSums(is.nan(omic_data)) < 0.05*nrow(omic_data)]

# Filter features by variance
feature_vars <- apply(omic_data, 2, function(v) var(v, na.rm=TRUE))
min_var <- quantile(feature_vars, 1-var_filter)
omic_data <- omic_data[,feature_vars >= min_var]

# Stick to simple/inexpensive median imputation for now.
# (Reduces impact on KCDF estimates??)
omic_data <- median_impute(omic_data)


############################################
# RUN GSVA 

# Call GSVA with the given parameter settings.
curried_gsva <- function(omic_data, genesets){
    cat("Running GSVA...\n")
    omic_data <- t(omic_data)
    results <- gsva(omic_data, genesets, min.sz=minsize,
                    max.sz=maxsize, kcdf=kcdf, parallel.sz=threads)
    return(t(results))
}

fitted_model <- list()

gsva_results <- curried_gsva(omic_data, genesets)
used_pwys <- colnames(gsva_results)

fitted_model[["used_genes"]] <- colnames(omic_data)
fitted_model[["used_pathways"]] <- used_pwys

############################################
## RUN PCA
#
#pca_result <- nipals(gsva_results, ncomp=output_dim)
#
#X <- pca_result$scores
#
#fitted_model[["mu"]] <- pca_result$center
#fitted_model[["sigma"]] <- pca_result$scale
#fitted_model[["Y"]] <- t(pca_result$loadings)
#fitted_model[["R2"]] <- pca_result$R2

###########################################
# SAVE FITTED MODEL AND TRANSFORMED DATA

saveRDS(fitted_model, fitted_model_rds)

# Need to get the target data
target <- h5read(data_hdf, "target")

h5write(gsva_results, transformed_hdf, "X")
h5write(rownames(gsva_results), transformed_hdf, "instances")
h5write(instance_groups, transformed_hdf, "instance_groups")
h5write(pwy_names, transformed_hdf, "feature_names")
h5write(target, transformed_hdf, "target") 


