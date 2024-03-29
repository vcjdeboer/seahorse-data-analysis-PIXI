
###
# pixi (‘R-integrated pixel intensity (PIXI) analysis’) 
# Vincent de Boer
#
# version 1.1
#
# update 29 jan 2022
# * added code for 2 dimensional tiff images 
# * added a variable to more easily set the postition of the wellname in the filename
# * added links to Ebimage resources
# * did some formatting
# * added inspection sections
#
# Packages needed EBImage, stringr, tidyverse
# please install other packages if needed as well.
#
# Tips:
# * input filename of the TIF files is IMPORTANT. The input filename is now set to be for a default Cytation Gen5 file naming convention
# That means it should be similar to "Bright Field_D7_1_001.tif"
# More specifically: the second string between underscores is assumed to be the wellname (this is default for Cytation Gen5)
# Even more specifically: the function "str_split" from the stringr package splits up the filename into strings with the
# underscore as separating character. It is now set that the second string from the left is the wellname (tempString <- str_split(fileNameToconvert, fixed("_"), simplify = TRUE)[,2])
#
# * input format of the TIF file is important, we noticed that some TIF files from cytation output have one channel (or frame) and others have 4 channels (or frames)
# this impacts the calculation and writing of the newly generated tif files.
#
# * The script outputs both the total intensity of all non background pixels ("total_intensity") and the
# number of non-black pixels ("non_blackPixels"), that can both be used for normalizing Seahorse data.
# The "total_intensity" was used in the Janssen et al 2021 Scientific reports paper.
# 
# FOR MORE INFO ABOUT THE IMAGE PROCESSING HAVE A LOOK AT:
# https://bioconductor.org/packages/release/bioc/vignettes/EBImage/inst/doc/EBImage-introduction.html
# The gblur and background correction was directed taken fromm that script
# Also, find the link to the original paper: here https://doi.org/10.1093/bioinformatics/btq046
# And the bioconductor landing page: https://bioconductor.org/packages/release/bioc/html/EBImage.html
# And another great resource: https://www.huber.embl.de/msmb/Chap-Images.html
# And another one: https://www.r-bloggers.com/2014/09/r-image-analysis-using-ebimage/

# This script is associated with:
# "Novel standardized method for extracellular flux analysis of oxidative and glycolytic metabolism in peripheral blood mononuclear cells"
# Janssen et al. 2021 Scientific Reports 11:1662
# https://rdcu.be/cebd6
#


## libraries 
library(EBImage)
library(stringr)
library(tidyverse)

# functions ---------------------------------------------------------------

## constants
  sigma_gblur <- 10 # defines the sigma constant in the gblur convolution function to generate the background image
  cropsize <- 0.05 #crop size in percentage (it takes eg. 5% (0.05) from each border away) (50% is the max because then 1 pixel is left then)

## functions
  final_image<- function (fileName){
    
    #fileName <- tif_file #for debugging
    img <- readImage(fileName)
    colorMode(img) <- Grayscale
  
    # make blurred image for background substraction
    img_bg <- gblur(img, sigma = sigma_gblur)
    
    # substract background image (mean or median is not different)
    img_bgcorr<-img+(abs(median(img_bg) - img_bg)) # absolute is needed here because else white pixels will be more grey
    img_bgcorr[img_bgcorr>1] <- 1
    img_bgcorr_invert <- max(img_bgcorr) - img_bgcorr #invert bkgd image 
    
    final_image<-img_bgcorr_invert
    
  } # generates the processed image
  
  sum_allIntensities<-function(image){
    if (length(dim(img)) == 3){
      totalInt <- sum(image[,,1]) #takes the sum of all pixel intensity of first frame
    } else {
      totalInt <- sum(image)
    }
  } #gives back the sum of all intensities of all pixels

  count_blackPixels <- function(image){
    if (length(dim(img)) == 3){
      sum(image[,,1]==0)
    } else{
      sum(image==0)
    }
  }
  
  crop<-function(image, crop_percentage){
    # image <- img #for debugging
    # crop_percentage <- cropsize #for debugging
    
    leftBound <- round((crop_percentage)*(nrow(image)))
    rightBound <- round((nrow(image)-(crop_percentage)*(nrow(image))))
    lowerBound <- round((crop_percentage)*(ncol(image)))
    upperBound <- round((ncol(image)-(crop_percentage)*(ncol(image))))
    ix <- leftBound:rightBound
    iy <- lowerBound:upperBound
    
    if (length(dim(image)) == 3){
      cropped_image <- image[ix,iy,]
    } else{
      cropped_image <- image[ix,iy]
    }
    
    crop <- cropped_image
  } # crops the Tif file


# script ------------------------------------------------------------------


# Assuming that image files are in the data folder
  base_dir <- c("data/")
  path <- paste0(getwd(), "/",base_dir)
  
# file_list_tifs will contain all filenames of the tifs that will be analyzed
  file_list_tifs = list.files(base_dir,pattern = "*.tif")
  file_list_tifs <- c(paste0(base_dir, file_list_tifs))
  
# declaration of variables
  df1 <- NULL
  df2 <- NULL

# df2 is the output of the analysis it calculates total_intensity and non_blackPixels
  for (tif_file in file_list_tifs){
    
    #tif_file <- file_list_tifs[1] #for debugging
    img <- final_image(tif_file) #read image
    img <- crop(img, cropsize) #crop image
    
    intensity <- sum_allIntensities(img)
    count <- count_blackPixels(img)

    df1 <- tibble(filename = tif_file, 
                     total_intensity = intensity,
                     count_blackPixels = count,
                     non_blackPixels = (nrow(img)*ncol(img)) - count,
                     totalPixels_inImage = nrow(img)*ncol(img),
                     crop = cropsize, 
                  sigma_gblur = sigma_gblur, 
                  directory=basename(path), 
                  date = Sys.Date()
                    )
    df2 <- rbind(df2, df1)
  }

# in the next for loop a wellname column will be added to df2 
  df2$Well <- 0
  whereis_wellname_in_string <- 2
  for (i in 1:nrow(df2)){
    fileNameToconvert <- df2$filename[i]
    tempString <- str_split(fileNameToconvert, fixed("_"), simplify = TRUE)[,whereis_wellname_in_string]
    
    # add a zero between letter and number if wellname has 2 characters
    if (nchar(tempString) ==  2) { 
      wellName <- sub("(.{1})(.*)", "\\10\\2", tempString)
    } else {
      wellName <- tempString
    }
    
    df2$Well[i] <- wellName
  }

# write output csv file ---------------------------------------------------

# write the output table to a csv file (change output filename here if needed)
  outputFILENAME <- "outputFilename.csv"
  getwd()
  write.table(df2, file = outputFILENAME, sep = ",",
              qmethod = "double", col.names = NA)


# inspection --------------------------------------------------------------

glimpse(df2)  
  
# simple inspect image from the list
  
  # take an image from the file list
  my_file_index = 1
  tif_file <- file_list_tifs[my_file_index] 
  img <- readImage(tif_file)
  display(img)
  # do background substraction
  img <- final_image(tif_file)
  display(img)
  # do crop
  img <- crop(img, cropsize) #crop image
  display(img)

# inspect background gblur image correction
  
  # take an image from the file list
  my_file_index = 1
  tif_file <- file_list_tifs[my_file_index]
  img <- readImage(tif_file)
  colorMode(img) <- Grayscale
  display(img)
  #make gblur background
  img_bg <- gblur(img, sigma = sigma_gblur)
  display(img_bg)
  # do background substraction
  img_bgcorr<-img+(abs(median(img_bg) - img_bg)) # absolute is needed here because else white pixels will be more grey
  display(img_bgcorr)
  # invert image
  img_bgcorr[img_bgcorr>1] <- 1
  img_bgcorr_invert <- max(img_bgcorr) - img_bgcorr #invert bkgd image 
  display(img_bgcorr_invert)
  

