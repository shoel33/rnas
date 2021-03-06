#!/usr/bin/env Rscript

# Read CT filename as a command line argument.
args <-commandArgs(TRUE)
# Check if anything was read.
if (length(args) ==0) {
  cat("Usage: ./RsampleCluster.R stochastic_sample.ct\n")
  stop("CT file with stochastic sample not provided.\n")
}
# Check if CT file exists.
filename <-as.character(args[1])
if ( !file.exists(filename) ) {
  stop("CT file with stochastic sample: ",filename," does not exist.\n")
}

# Alternatively, if one wishes to run the script from within R,
# filename should be provided in the following line and all the lines above
# should be commented out.
#filename="stochastic.1000.ct"

name=strsplit(filename,".ct")
cat("Filename: ",filename,"\n")
# Cluster into optimal # of clusters or specified number of clusters.
# If type=0 optimal # of clusters will be determined, otherwise number specified
# in type variable will be used
type=0
if ( type > 1) cat('Clustering into',type,'clusters\n')

# Get number of nucleotides and conformations.
no_nucl<-scan(file=filename,what=integer(),nmax=1,nlines=1)
no_lines<-length(readLines(filename))
no_struct <- no_lines/(no_nucl+1)
confi <- matrix(NA_integer_, nrow=no_struct, ncol=no_nucl)
# Read sequence from CT file.
seq <- as.matrix(read.table(filename,skip=1,nrows=no_nucl,colClasses=c("NULL","character","NULL","NULL","NULL","NULL")))
# Read the whole CT file.
for (i in 1:no_struct) {
  confi[i,] <- as.matrix(read.table(filename,header=FALSE,nrows=no_nucl,skip=(i-1)*(no_nucl+1)+1,colClasses=c("NULL","NULL","NULL","NULL","integer","NULL")))
}
# Make pairing data matrix.
pairing_data <-array(0L,dim=c(no_struct,no_nucl,no_nucl))
for (i in 1:no_struct) {
  for (j in 1:no_nucl) {
    if (confi[i,j] != 0) {
      pairing_data[i,j,confi[i,j]] <- 1L
    }
  }
}
# Calculate distance matrix
# Get about 2x speedup by using Fortran to compute distance_matrix.
# Files calcdistf90.R and calcdist.f90 are in Rsample directory. They
# should be in same directory as this file.
if ( file.exists("calcdistf90.R") && file.exists("calcdist.so") ) {
  source("calcdistf90.R")
  distance_matrix <- calcdistf90(pairing_data)
} else {
  # use R to compute distance_matrix. This is 2x slower than Fortran.
  distance_matrix <- matrix(NA_integer_, nrow=no_struct, ncol=no_struct)
  for (i in 1:no_struct) {
    for (j in 1:no_struct) {
      distance_matrix[i,j] <- sum(abs(pairing_data[i,,]-pairing_data[j,,]))
    }
  }
}

# Do Diana clustering.
dv <- cluster::diana(distance_matrix,diss=TRUE,metric="manhattan",stand=TRUE)
# Split dv into clusters of size 2 to 10
dvc <- matrix(NA_real_, nrow=9, ncol=no_struct)
for (i in 1:9) {
  dvc[i,] <- cutree(dv,k=i+1)
}
# Calculate CH index for each cluster size using CH index.
ch_ind <- double(9)
for (i in 1:9) {
  temp <- fpc::cluster.stats(distance_matrix,dvc[i,])
  ch_ind[i] <- temp$ch
}
# Find cluster with max CH index.
if (type == 0 ) opt_clust_size <- which.max(ch_ind) else opt_clust_size <- type-1
# Find centroids of clusters and number of elements in each cluster.
clust_size <- integer(opt_clust_size+1)
for (i in 1:(opt_clust_size+1)) {
  clust_size[i] <- length(which(dvc[opt_clust_size,]==i))
}
cat("Optimal # of clusters:",opt_clust_size+1,"\n")
for (i in 1:(opt_clust_size+1)) {
  cat("Size of cluster",i,clust_size[i])
  cat("\n")
}
# Calculate average # of bps in each cluster.
bp_sum_cluster <- array(NA_real_,dim=c(opt_clust_size+1,no_nucl,no_nucl))
for (i in 1:(opt_clust_size+1)) {
  # temp is a subset of pairing_data matrix which belong to a same cluster
  temp <- array(0,dim=c(clust_size[i],no_nucl,no_nucl))
  temp <- pairing_data[which(dvc[opt_clust_size,]==i),,]
  # If one dimension is 1 i.e. if cluster has 1 element then temp[,j,k] crashes so one needs to separate the cases 
  if (clust_size[i] > 1) 
    for (j in 1:no_nucl) {
      for (k in 1:no_nucl) {
        bp_sum_cluster[i,j,k] <- sum(temp[,j,k]/clust_size[i])
      }
    }
  else
    for (j in 1:no_nucl) {
      for (k in 1:no_nucl) {
        bp_sum_cluster[i,j,k] <- sum(temp[j,k]/clust_size[i])
      }
    }  
}
# Find max and bp_probability for every nt in every cluster.
max_position_cluster <- array(NA_integer_,dim=c(opt_clust_size+1,no_nucl))
bp_prob_cluster <- array(NA_real_,dim=c(opt_clust_size+1,no_nucl))
for (i in 1:(opt_clust_size+1)) {
  for (j in 1:no_nucl) {
    max_position_cluster[i,j] <- which.max(bp_sum_cluster[i,j,])
    bp_prob_cluster[i,j] <- bp_sum_cluster[i,j,max_position_cluster[i,j]]
  }
}
# Determine centroid by using only probability > 0.5.
centroid <- array(0L,dim=c(opt_clust_size+1,no_nucl))
for (i in 1:(opt_clust_size+1)) {
  for (j in 1:no_nucl) {
    if (bp_prob_cluster[i,j] > 0.5) {
      centroid[i,j] <- max_position_cluster[i,j]
    }
  }
}
# Print centroid structures to files.
for (i in 1:(opt_clust_size+1)) {
  cat(no_nucl,as.character(name),"centroid",i,"\n",file=paste(as.character(name),".centroid.",i,".ct",sep=""),append=FALSE)
  for (j in 1:no_nucl) {
    cat(j,seq[j],j-1,j+1,centroid[i,j],j,"\n",sep="  ",file=paste(as.character(name),".centroid.",i,".ct",sep=""),append=TRUE)
  }
}
