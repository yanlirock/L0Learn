#' @title Cross Validation
#'
#' @inheritParams L0Learn.fit
#' @description Computes a regularization path and performs K-fold cross-validation.
#' @param nFolds The number of folds for cross-validation.
#' @param seed The seed used in randomly shuffling the data for cross-validation.
#' @return An S3 object of type "L0LearnCV" describing the regularization path. The object has the following members.
#' \item{cvMeans}{This is a list, where the ith element is the sequence of cross-validation errors corresponding to the ith gamma value, i.e., the sequence
#' cvMeans[[i]] corresponds to fit$gamma[i]}
#' \item{cvSDs}{This a list, where the ith element is a sequence of standard deviations for the cross-validation errors: cvSDs[[i]] corresponds to cvMeans[[i]].}
#' \item{fit}{The fitted model with type "L0Learn", i.e., this is the same object returned by \code{\link{L0Learn.fit}}.}
#'
#' @examples
#' # Generate synthetic data for this example
#' data <- GenSynthetic(n=500,p=1000,k=10,seed=1)
#' X = data$X
#' y = data$y
#'
#' # Perform 5-fold cross-validation on an L0L2 regression model with 5 values of
#' # Gamma ranging from 0.0001 to 10
#' fit <- L0Learn.cvfit(X, y, nFolds=5, seed=1, penalty="L0L2", maxSuppSize=20, nGamma=5,
#' gammaMin=0.0001, gammaMax = 10)
#' print(fit)
#' # Plot the graph of cross-validation error versus lambda for gamma = 0.0001
#' plot(fit, gamma=0.0001)
#' # Extract the coefficients at lambda = 0.0361829 and gamma = 0.0001
#' coef(fit, lambda=0.0361829, gamma=0.0001)
#' # Apply the fitted model on X to predict the response
#' predict(fit, newx = X, lambda=0.0361829, gamma=0.0001)
#'
#' @export
L0Learn.cvfit <- function(x,y, loss="SquaredError", penalty="L0", algorithm="CD", maxSuppSize=100, nLambda=100, nGamma=10,
						gammaMax=10, gammaMin=0.0001, partialSort = TRUE, maxIters=200,
						tol=1e-6, activeSet=TRUE, activeSetNum=3, maxSwaps=100, scaleDownFactor=0.8, screenSize=1000, autoLambda = TRUE, lambdaGrid = list(0), nFolds=10, seed=1, excludeFirstK=0, intercept=TRUE)
{
	set.seed(seed)

	# Some sanity checks for the inputs
	if ( !(loss %in% c("SquaredError","Logistic","SquaredHinge")) ){
			stop("The specified loss function is not supported.")
	}
	if ( !(penalty %in% c("L0","L0L2","L0L1")) ){
			stop("The specified penalty is not supported.")
	}
	if ( !(algorithm %in% c("CD","CDPSI")) ){
			stop("The specified algorithm is not supported.")
	}
	if (loss=="Logistic" | loss=="SquaredHinge"){
			if (dim(table(y)) != 2){
					stop("Only binary classification is supported. Make sure y has only 2 unique values.")
			}
			y = factor(y,labels=c(-1,1)) # returns a vector of strings
			y = as.numeric(levels(y))[y]

			if (penalty == "L0"){
					# Pure L0 is not supported for classification
					# Below we add a small L2 component.
					penalty = "L0L2"
					nGamma = 1
					gammaMax = 1e-7
					gammaMin = 1e-7
			}
	}

	# The C++ function uses LambdaU = 1 for user-specified grid. In R, we use AutoLambda0 = 0 for user-specified grid (thus the negation when passing the parameter to the function below)
	M <- .Call('_L0Learn_L0LearnCV', PACKAGE = 'L0Learn', x, y, loss, penalty, algorithm, maxSuppSize, nLambda, nGamma, gammaMax, gammaMin, partialSort, maxIters, tol, activeSet, activeSetNum, maxSwaps, scaleDownFactor, screenSize, !autoLambda, lambdaGrid, nFolds, seed, excludeFirstK, intercept)

	settings = list()
	settings[[1]] = intercept # Settings only contains intercept for now. Might include additional elements later.
	names(settings) <- c("intercept")

	# Find potential support sizes exceeding maxSuppSize and remove them (this is due to
	# the C++ core whose last solution can exceed maxSuppSize
	for (i in 1:length(M$SuppSize)){
			last = length(M$SuppSize[[i]])
			if (M$SuppSize[[i]][last] > maxSuppSize){
					if (last == 1){
							print("Warning! Only 1 element in path with support size > maxSuppSize.")
							print("Try increasing maxSuppSize to resolve the issue.")
					}
					else{
							M$SuppSize[[i]] = M$SuppSize[[i]][-last]
							M$Converged[[i]] = M$Converged[[i]][-last]
							M$lambda[[i]] = M$lambda[[i]][-last]
							M$a0[[i]] = M$a0[[i]][-last]
							M$beta[[i]] = as(M$beta[[i]][,-last], "sparseMatrix") # conversion to sparseMatrix is necessary to handle the case of a single column
							M$CVMeans[[i]] = M$CVMeans[[i]][-last]
							M$CVSDs[[i]] = M$CVSDs[[i]][-last]
					}
			}
	}

	fit <- list(beta = M$beta, lambda=lapply(M$lambda,signif, digits=6), a0=M$a0, converged = M$Converged, suppSize= M$SuppSize, gamma=M$gamma, penalty=penalty, loss=loss, settings=settings)
	if (is.null(colnames(x))){
			varnames <- 1:dim(x)[2]
	} else {
			varnames <- colnames(x)
	}
	fit$varnames <- varnames
	class(fit) <- "L0Learn"
	fit$n <- dim(x)[1]
	fit$p <- dim(x)[2]
	G <- list(fit=fit, cvMeans=M$CVMeans,cvSDs=M$CVSDs)
	class(G) <- "L0LearnCV"
	G
}
