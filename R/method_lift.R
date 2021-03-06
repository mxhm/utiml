#' LIFT for multi-label Classification
#'
#' Create a multi-label learning with Label specIfic FeaTures (LIFT) model.
#'
#' LIFT firstly constructs features specific to each label by conducting
#' clustering analysis on its positive and negative instances, and then performs
#' training and testing by querying the clustering results.
#'
#' @family Transformation methods
#' @param mdata A mldr dataset used to train the binary models.
#' @param base.algorithm A string with the name of the base algorithm. (Default:
#'  \code{options("utiml.base.algorithm", "SVM")})
#' @param ratio Control the number of clusters being retained. Must be between
#'  0 and 1. (Default: \code{0.1})
#' @param ... Others arguments passed to the base algorithm for all subproblems.
#' @param cores The number of cores to parallelize the training. Values higher
#'  than 1 require the \pkg{parallel} package. (Default:
#'  \code{options("utiml.cores", 1)})
#' @param seed An optional integer used to set the seed. This is useful when
#'  the method is run in parallel. (Default: \code{options("utiml.seed", NA)})
#' @return An object of class \code{LIFTmodel} containing the set of fitted
#'   models, including:
#'   \describe{
#'    \item{labels}{A vector with the label names.}
#'    \item{models}{A list of the generated models, named by the label names.}
#'   }
#' @references
#'  Zhang, M.-L., & Wu, L. (2015). Lift: Multi-Label Learning with
#'  Label-Specific Features. IEEE Transactions on Pattern Analysis and Machine
#'  Intelligence, 37(1), 107-120.
#' @export
#'
#' @examples
#' model <- lift(toyml, "RANDOM")
#' pred <- predict(model, toyml)
#'
#' \dontrun{
#' # Runing lift with a specific ratio
#' model <- lift(toyml, "RF", 0.15)
#' }
lift <- function(mdata,
                 base.algorithm = getOption("utiml.base.algorithm", "SVM"),
                 ratio = 0.1, ..., cores = getOption("utiml.cores", 1),
                 seed = getOption("utiml.seed", NA)) {
  # Validations
  if (class(mdata) != "mldr") {
    stop("First argument must be an mldr object")
  }

  if (cores < 1) {
    stop("Cores must be a positive value")
  }

  if (ratio < 0 || ratio > 1) {
    stop("The attribbute ratio must be between 0 and 1")
  }

  #TODO parametrize clustering and distance method
  utiml_preserve_seed()

  # LIFT Model class
  liftmodel <- list(labels = rownames(mdata$labels),
                    ratio = ratio, call = match.call())

  # Create models
  mldataset <- rep_nom_attr(mdata$dataset[mdata$attributesIndexes], TRUE)
  labels <- utiml_rename(liftmodel$labels)
  liftdata <- utiml_lapply(labels, function (label) {
    #Form Pk and Nk based on D according to Eq.(1)
    Pk <- mdata$dataset[,label] == 1
    Nk <- !Pk

    #Perform k-means on Pk and Nk, each with mk clusters as defined in Eq.(2)
    mk <- ceiling(ratio * min(sum(Pk), sum(Nk)))

    gpk <- stats::kmeans(mldataset[Pk, ], mk)
    gnk <- stats::kmeans(mldataset[Nk, ], mk)
    centroids <- rbind(gpk$centers, gnk$centers)
    rownames(centroids) <- c(paste("p", rownames(gpk$centers), sep=''),
                             paste("n", rownames(gnk$centers), sep=''))

    #Create the mapping k for lk according to Eq.(3);
    dataset <- cbind(utiml_euclidean_distance(mldataset, centroids),
                     mdata$dataset[label])
    colnames(dataset) <-  c(rownames(centroids), label)

    #Induce the model using the base algorithm
    model <- utiml_create_model(
      utiml_prepare_data(dataset, "mldLIFT", mdata$name,
                         "lift", base.algorithm),
      ...
    )

    rm(dataset)
    list(
      centroids = centroids,
      model = model
    )
  }, cores, seed)

  liftmodel$centroids <- lapply(liftdata, function (x) x$centroids)
  liftmodel$models <- lapply(liftdata, function (x) x$model)

  utiml_restore_seed()

  class(liftmodel) <- "LIFTmodel"
  liftmodel
}

#' Predict Method for LIFT
#'
#' This function predicts values based upon a model trained by
#' \code{\link{lift}}.
#'
#' @param object Object of class '\code{LIFTmodel}'.
#' @param newdata An object containing the new input data. This must be a
#'  matrix, data.frame or a mldr object.
#' @param probability Logical indicating whether class probabilities should be
#'  returned. (Default: \code{getOption("utiml.use.probs", TRUE)})
#' @param ... Others arguments passed to the base algorithm prediction for all
#'   subproblems.
#' @param cores The number of cores to parallelize the training. Values higher
#'  than 1 require the \pkg{parallel} package. (Default:
#'  \code{options("utiml.cores", 1)})
#' @param seed An optional integer used to set the seed. This is useful when
#'  the method is run in parallel. (Default: \code{options("utiml.seed", NA)})
#' @return An object of type mlresult, based on the parameter probability.
#' @seealso \code{\link[=lift]{LIFT}}
#' @export
#'
#' @examples
#' model <- lift(toyml, "RANDOM")
#' pred <- predict(model, toyml)
predict.LIFTmodel <- function(object, newdata,
                            probability = getOption("utiml.use.probs", TRUE),
                            ..., cores = getOption("utiml.cores", 1),
                            seed = getOption("utiml.seed", NA)) {
  # Validations
  if (class(object) != "LIFTmodel" && class(object) != "MLDFLmodel") {
    stop("First argument must be an LIFTmodel/MLDFLmodel object")
  }

  if (cores < 1) {
    stop("Cores must be a positive value")
  }

  utiml_preserve_seed()

  # Predict models
  newdata <- rep_nom_attr(utiml_newdata(newdata), TRUE)
  labels <- utiml_rename(object$labels)
  predictions <- utiml_lapply(labels, function (label) {
    centroids <- object$centroids[[label]]
    dataset <- as.data.frame(utiml_euclidean_distance(newdata, centroids))
    dimnames(dataset) <- list(rownames(newdata), rownames(centroids))
    utiml_predict_binary_model(object$models[[label]], dataset, ...)
  }, cores, seed)

  utiml_restore_seed()

  utiml_predict(predictions, probability)
}

#' Print LIFT model
#' @param x The lift model
#' @param ... ignored
#' @export
print.LIFTmodel <- function(x, ...) {
  cat("LIFT Model\n\nCall:\n")
  print(x$call)
  cat("\nRatio:", x$ratio, "\n")
  cat("\n", length(x$labels), "Binary Models:\n")
  overview <- as.data.frame(cbind(label=names(x$centroids),
                                  attrs=unlist(lapply(x$centroids, nrow))))
  rownames(overview) <- NULL
  print(overview)
}

# Calculate the euclidian distance for two sets of data
utiml_euclidean_distance <- function(x, y) {
  x <- t(x)
  apply(y, 1, function (row) sqrt(colSums((x - row) ^ 2)))
}
