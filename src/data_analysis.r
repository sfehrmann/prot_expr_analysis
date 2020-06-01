#!/usr/bin/env Rscript

# required 
library(readxl)
library(ggplot2)
library(ggfortify) # required for autoplot
library(tidyr)
library(dplyr)
library(visdat) # required for vis_miss
library(tibble)
library(limma)
library(RColorBrewer)
library(pheatmap)

source('src/helper_functions.R')

# load raw data from excel
prot_exp_raw <- read_excel("data_052020/Protein_Exp__FeatureLevel_artificial.xlsx", 
                       sheet = "Sheet 1",
                       col_names = TRUE,
                       na = "NA")

# split feature pattern and sum by protein, ungroup after operation
prot_exp <- prot_exp_raw %>%
  separate(Feature, c('Protein', 'Peptide', 'Charge'), sep = '_', remove = TRUE) %>%
  group_by(Protein) %>%
  summarise_at(vars(Pool1_126:Pool2_131N), sum, na.rm = TRUE) %>%
  ungroup()

# visualization of missing values
vis_miss(prot_exp[,2:20]) # no missing values after summa
vis_miss(prot_exp_raw[,2:20]) # batch pattern visible here

# box plot to explore data distribution
pr_expr_box_plot(prot_exp)

########### prep for PCA
# read annotation
sample_annotation <- read_excel("data_052020/ExpDesign.xlsx",
                                col_names = TRUE)

# transpose (Feature is the name of the first column) and add annotation
tr_prot_exp_annotated <- prot_exp %>% 
  gather(sample_name, values, 2:ncol(prot_exp)) %>%
  spread(Protein, values) %>%
  add_column(sample_annotation, .after = "sample_name")

# compute and plot PCA
my_scaled_pca <- prcomp(tr_prot_exp_annotated[7:ncol(tr_prot_exp_annotated)], scale. = TRUE)
autoplot(my_scaled_pca, data=tr_prot_exp_annotated, colour = 'Pool', shape = 'Condition', scale = 0)

###### NA handling
# NA problem solved by summarizing by proteins
# leaving here for educational purpose

# replace 
tr_prot_exp_no_NA <- tr_prot_exp_annotated %>%
  gather(protein, expression_values, 7:ncol(tr_prot_exp_annotated)) %>%
  mutate(expression_values = replace_na(expression_values, 0)) %>%
  spread(protein, expression_values)

tr_prot_exp_track_NA <- tr_prot_exp_annotated %>%
  gather(protein, expression_values, 7:ncol(tr_prot_exp_annotated)) %>%
  mutate(expression_values, was_NA = is.na(expression_values), .before = expression_values) %>%
  select(sample_name:was_NA) %>%
  spread(protein, was_NA)


my_scaled_pca_2 <- prcomp(tr_prot_exp_no_NA[7:ncol(tr_prot_exp_no_NA)], scale. = T)
autoplot(my_scaled_pca_2, data=tr_prot_exp_no_NA, colour = 'Pool', shape = 'Condition', scale = 0)

# depends on vqv-ggbiplot
# ggbiplot(my_scaled_pca_2, ellipse=TRUE,  labels=tr_prot_exp_no_NA$Sample, groups=tr_prot_exp_no_NA$Pool)

# remove batch effect
prot_exp_matrix <- as.matrix(prot_exp[,2:20])
prot_exp_matrix_corrected <- removeBatchEffect(prot_exp_matrix, sample_annotation$Pool)

# back to tibble
prot_exp_cor <- prot_exp
prot_exp_cor[,2:20] <- prot_exp_matrix_corrected
pr_expr_box_plot(prot_exp_cor)

RepBinary <- c("Rep1-3", "Rep1-3", "Rep1-3", "Rep1-3", "Rep4-6", "Rep1-3", "Rep1-3", "Rep4-6", "Rep4-6", "Rep4-6", "Rep4-6", "Rep1-3", "Rep1-3", "Rep1-3", "Rep1-3", "Rep4-6", "Rep1-3", "Rep1-3", "Rep4-6")
# transpose (Feature is the name of the first column) and add annotation
tr_prot_exp_cor_annotated <- prot_exp_cor %>% 
  gather(sample_name, values, 2:ncol(prot_exp_cor)) %>%
  spread(Protein, values) %>%
  add_column(sample_annotation, .after = "sample_name") %>%
  add_column(RepBinary, .after = "BioRep")

# compute and plot PCA
my_scaled_pca <- prcomp(tr_prot_exp_cor_annotated[8:ncol(tr_prot_exp_cor_annotated)], scale. = TRUE)
autoplot(my_scaled_pca, data=tr_prot_exp_cor_annotated, colour = 'Condition', shape = 'RepBinary', scale = 0)
# possible mislabeling of sample 17 (Rep3/Cond3)
autoplot(my_scaled_pca, data=tr_prot_exp_cor_annotated, colour = 'Condition', shape = 'BioRep', scale = 0)

# compute variance and keep top 2% only
prot_exp_cor_top2perc <- prot_exp_cor %>%
  rowwise() %>%
  mutate(variance = var(c_across(starts_with("Pool")))) %>%
  ungroup() %>%
  slice_max(variance, prop = 0.02)

# check dependence mean / variance
prot_exp_cor_mnvar <- prot_exp_cor %>%
  rowwise() %>%
  mutate(variance = var(c_across(starts_with("Pool"))),
         mean = mean(c_across(starts_with("Pool"))),
         median = median(c_across(starts_with("Pool"))))

ggplot(prot_exp_cor_mnvar, aes(x=median, y= variance)) +
  geom_point() +
  scale_x_continuous(trans = 'log10') +
  scale_y_continuous(trans = 'log10') +
  geom_smooth(method=lm)

prot_exp_matrix_cor_top2perc <- as.matrix(prot_exp_cor_top2perc[2:20])
rownames(prot_exp_matrix_cor_top2perc) <- prot_exp_cor_top2perc$Protein
colnames(prot_exp_matrix_cor_top2perc) <- paste(sample_annotation$Condition, '/', sample_annotation$BioRep, sep='')
color_vec <- colorRampPalette(brewer.pal(9, "YlOrRd"))(255)
color_vec <- colorRampPalette(brewer.pal(9, "Blues"))(255)
# as expected, not very expressive
pheatmap(prot_exp_matrix_cor_top2perc,col=color_vec)

# two values are less than 0, replace with a values slightly lower than the next lowest
prot_exp_matrix_cor_top2perc[prot_exp_matrix_cor_top2perc<0] <- 6
pheatmap(log10(prot_exp_matrix_cor_top2perc),col=color_vec)

ggplot(prot_exp_cor, aes(x=Pool1_126, y=Pool2_130N)) +
  geom_point() +
  scale_x_continuous(trans = 'log10') +
  scale_y_continuous(trans = 'log10')
