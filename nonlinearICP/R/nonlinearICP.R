#' Nonlinear Invariant Causal Prediction
#'
#' @param X A (nxp)-dimensional matrix (or data frame) with n observations of p variables.
#' @param Y A (nx1)-dimensional response vector.
#' @param environment Environment variable(s) in an (n x k)-dimensional
#' matrix or dataframe. Note that not all nonlinear conditional
#' independence tests may support more than one environmental variable.
#' @param condIndTest Function implementing a conditional independence test (see below
#' for the required interface). Defaults to \code{InvariantResidualDistributionTest} from
#' the package \code{CondIndTests}.
#' @param argsCondIndTest Arguments of \code{condIndTest}. Defaults to \code{NULL}.
#' @param alpha Significance level to be used. Defaults to \code{0.05}.
#' @param varPreSelectionFunc Variable selection function that is applied
#' to pre-select a set of variables before running the ICP procedure on the resulting
#' subset. Should be used with care as causal parents might be excluded in this step.
#' Defaults to \code{NULL}.
#' @param argsVarPreSelectionFunc Arguments of \code{varPreSelectionFunc}.
#' Defaults to \code{NULL}.
#' @param maxSizeSets Maximal size of sets considered as causal parents.
#' Defaults to \code{ncol(X)}.
#' @param condIndTestNames Name of conditional independence test, used for printing.
#'  Defaults to \code{NULL}.
#' @param speedUp Use subsamples of sizes specified in \code{subsampleSize} to speed
#' up the test for sets where the null hypothesis can already be rejected based on
#' a small number of samples (a larger sample size would potentially further
#' decrease the p-value but would not change the decision, i.e. the set is rejected
#' in any case). Applies Bonferroni multiple testing correction.
#' Defaults to \code{FALSE}.
#' @param subsampleSize Size of subsamples used in \code{speedUp} procedure
#'  as fraction of total sample size. Defaults to \code{c(0.1, 0.25, 0.5, 0.75, 1)}.
#' @param retrieveDefiningsSets Boolean variable to indicate whether defining sets
#' should be retrieved. Defaults to \code{TRUE}.
#' @param seed Random seed.
#' @param stopIfEmpty Stop ICP procedure if retrieved set is empty. If
#' \code{retrieveDefiningsSets} is \code{TRUE}, setting \code{stopIfEmpty} to
#' \code{TRUE} results in testing further sets to retrieve the defining sets. However,
#'  setting \code{stopIfEmpty} to \code{TRUE} in this case will still speedup the procedure as
#'  some sets will not be tested (namely those where accepting/rejecting
#'  would not affect the defining sets). Setting \code{stopIfEmpty} to
#' \code{FALSE} means that all possible subsets of the predictors are tested.
#' @param testAdditionalSet If a particular set should be tested, the corresponding
#'  indices can be provided via this argument.
#' @param verbose Boolean variable to indicate whether messages should be printed.
#'
#' @return A list with the following elements:
#' \itemize{
#' \item \code{retrievedCausalVars} Indices of variables in \eqn{\hat{S}}
#' \item \code{acceptedSets} List of accepted sets.
#' \item \code{definingSets}  List of defining sets.
#' \item \code{acceptedModels} List of accepted models if specified in \code{argsCondIndTest}.
#' \item \code{pvalues.accepted} P-values of accepted sets.
#' \item \code{rejectedSets} List of rejected sets.
#' \item \code{pvalues.rejected} P-values of rejected sets.
#' \item \code{settings} Settings provided to \code{nonlinearICP}.
#' }
#'
#' @details The function provided as \code{condIndTest} needs to take the following
#' arguments in the given order: \code{Y, environment, X, alpha, verbose}. Additional
#' arguments can then be provided via \code{argsCondIndTest}.
#'
#' @references Please cite
#' C. Heinze-Deml, J. Peters and N. Meinshausen: "Invariant Causal Prediction for Nonlinear Models",
#' \href{https://arxiv.org/abs/1706.08576}{arXiv:1706.08576}.
#'
#' @seealso The function \code{\link[CondIndTests]{CondIndTest}} from the package
#'  \code{CondIndTests} is a wrapper for a variety of nonlinear conditional independence
#'  tests that can be used in \code{condIndTest}.
#'
#' @examples
#' # Example 1
#' require(CondIndTests)
#' data("simData")
#' targetVar <- 2
#' # choose environments where we did not intervene on var
#' useEnvs <- which(simData$interventionVar[,targetVar] == 0)
#' ind <- is.element(simData$environment, useEnvs)
#' X <- simData$X[ind,-targetVar]
#' Y <- simData$X[ind,targetVar]
#' E <- as.factor(simData$environment[ind])
#' result <- nonlinearICP(X = X, Y = Y, environment = E)
#' cat(paste("Variable",result$retrievedCausalVars, "was retrieved as the causal
#' parent of target variable", targetVar))
#'
#' ###################################################
#'
#' # Example 2
#' E <- rep(c(1,2), each = 500)
#' X1 <- E + 0.1*rnorm(1000)
#' X1 <- rnorm(1000)
#' X2 <- X1 + E^2 + 0.1*rnorm(1000)
#' Y <- X1 + X2 + 0.1*rnorm(1000)
#' resultnonlinICP <- nonlinearICP(cbind(X1,X2), Y, as.factor(E))
#' summary(resultnonlinICP)
nonlinearICP <- function(X, Y, environment,
                         condIndTest = InvariantResidualDistributionTest,
                         argsCondIndTest = NULL,
                         alpha=0.05,
                         varPreSelectionFunc = NULL,
                         argsVarPreSelectionFunc = NULL,
                         maxSizeSets = ncol(X),
                         condIndTestNames = NULL,
                         speedUp = FALSE,
                         subsampleSize = c(0.1, 0.25, 0.5, 0.75, 1),
                         retrieveDefiningsSets = TRUE,
                         seed = 1,
                         stopIfEmpty = TRUE,
                         testAdditionalSet = NULL,
                         verbose = FALSE){

  set.seed(seed)

  # check inputs
  if (NROW(environment) != NROW(Y))
    stop("if `ExpInd' is a vector, it needs to have the same length as `Y'")

  uni <- unique(environment)
  if (length(uni) == 1)
    stop(paste("there is just one environment ('environment'=",
               uni[1], " for all observations) and the method needs at least two distinct environments",
               sep = ""))

  # retrieve number of observations and number of variables
  n <- NROW(X)
  p <- NCOL(X)

  if(is.null(colnames(X))) colnames(X) <- 1:p

  if(verbose) cat(paste("\n\n *** Using conditional independence test '",

                        if(!is.null(condIndTestNames)){
                          condIndTestNames[1]
                        }else{
                          deparse(substitute(condIndTest))
                        },

                        "' with test '",

                        if(class(argsCondIndTest$test) == "function"){
                          if(!is.null(condIndTestNames)){
                            condIndTestNames[2]
                          }else{
                            deparse(substitute(argsCondIndTest$test))
                          }
                        }else{
                          formals(condIndTest)$test
                        },

                        if(class(varPreSelectionFunc) == "function")
                          "' and variable selection." else "'.",
                        sep = ""))

  # get sets to test
  if(class(varPreSelectionFunc) == "function"){
    idxSelected <- do.call(varPreSelectionFunc,
                           c(list(X, Y, environment, verbose),
                             if(!is.null(argsVarPreSelectionFunc))
                               argsVarPreSelectionFunc
                             )
                           )
    # set maximal set size to min of number of chosen variables and provided option
    # limiting the set size
    maxSizeSets <- min(maxSizeSets, length(idxSelected))

    if(verbose)
      if(maxSizeSets > length(idxSelected))
        cat(paste("\n Maximal set size is", maxSizeSets))

    testsets <- getblanketall(idxSelected, maxSize = maxSizeSets)
  }else if(!is.null(varPreSelectionFunc)){
    warning("varPreSelectionFunc needs to be a function. Ignoring the argument.")
  }else{
    testsets <- getblanketall(1:p, maxSize = maxSizeSets)
  }

  # number of sets to test
  nSets <- length(testsets)

  # initialize list for accepted sets
  acceptedSets <- rejectedSets <- list()
  acceptedModels <- list()
  pvalues.accepted <- pvalues.rejected <- NULL

  # initialize control structure condition
  cont <- TRUE
  setCounter <- -1

  if(verbose) printoutat <- 2^(1:ceiling(log2(nSets)))

  # compute p-value
  while(cont && setCounter < nSets){
    if(verbose){
      if(setCounter %in% printoutat){

        cat(paste("\n\n *** ", round(100*setCounter/nSets),
                  "% complete: tested ", setCounter," of ", nSets,
                  " sets of variables ", sep=""))
      }
    }

    setCounter <- setCounter+1

    if(setCounter == 0){
      usevariab <- NULL
    }else{
      usevariab <- testsets[[setCounter]]
    }

    if(all(usevariab != 0)){
      if(verbose)
        cat(paste("\n\n ----- Testing variables ",
                  paste(usevariab,collapse=", "), " ----- ",sep=""))

      if(setCounter == 0){
        designMat <- matrix(rep(1, nrow(X)), nrow = nrow(X), ncol = 1)
      }else{
        designMat <- X[, usevariab,drop=FALSE]
      }

      pvalueAndDecision <- getPValueAndDecision(designMat,
                                                Y, environment,
                                                condIndTest = condIndTest,
                                                argsCondIndTest = argsCondIndTest,
                                                alpha=alpha,
                                                speedUp = speedUp,
                                                subsampleSize = subsampleSize,
                                                verbose = verbose)

      pvalue <- pvalueAndDecision$pvalue
      decision <- pvalueAndDecision$decision

      # accept is decision is 1
      if(decision == 1){
        if(verbose)
          cat(paste("\n  -----  Accepted set of variables ",
                    paste(usevariab,collapse=", "),
                    " with p-value ", pvalue, " -----" ,sep=""))

        if(is.null(usevariab)){
          acceptedSets[[length(acceptedSets)+1]] <- 0

        }else{
          acceptedSets[[length(acceptedSets)+1]] <- usevariab
        }

        if(!is.null(pvalueAndDecision$model)){
          acceptedModels[[length(acceptedModels)+1]] <- pvalueAndDecision$model
        }

        pvalues.accepted <- c(pvalues.accepted, pvalue)

        if(length(acceptedSets) >= 2){
          setIntersection <- computeSetIntersection(acceptedSets, verbose = verbose)
          nVars <- length(setIntersection)

          # we can stop if the intersection is empty, unless we want to compute
          # the defining sets
          if(nVars == 0){
            if(!retrieveDefiningsSets){
              cont <- FALSE
            }else{
              if(verbose)
                cat("\n\n  ----- Retrieving defining sets....")

              # retrieve last set that made intersection empty
              lastAcceptedSet <- acceptedSets[[length(acceptedSets)]]

              if(stopIfEmpty){
                # remove test sets containing all variables in the last accepted set
                # because rejecting or accepting these won't change the defining sets
                if(verbose)
                  cat(paste("\n\n  ----- Removing sets containing variable(s) ",
                            paste(lastAcceptedSet,collapse=", "), "-----" ,sep=""))


                  testsets[(setCounter+1):nSets] <-
                    lapply(testsets[(setCounter+1):nSets],
                           function(x) if(all(is.element(lastAcceptedSet, x))) 0 else x)
              }


            }
          }else{
            if(stopIfEmpty){
              # remove test sets containing all variables in the intersection
              # because rejecting or accepting these won't change the decision
              if(verbose)
                cat(paste("\n\n  ----- Removing sets containing variable(s) ",
                          paste(setIntersection,collapse=", "), "-----" ,sep=""))

              testsets[(setCounter+1):nSets] <-
                lapply(testsets[(setCounter+1):nSets],
                       function(x) if(all(is.element(setIntersection, x))) 0 else x)
            }

          }


        }else if(setCounter == 0){
          if(!retrieveDefiningsSets & stopIfEmpty){
            cont <- FALSE
            if(verbose){
             cat("\n\n  ----- Accepted empty set....")
            }
          }

        }
      }else{

        if(is.null(usevariab)){
          rejectedSets[[length(rejectedSets)+1]] <- 0
        }else{
          rejectedSets[[length(rejectedSets)+1]] <- usevariab
        }

        pvalues.rejected <- c(pvalues.rejected, pvalue)

        if(verbose)
          cat(paste("\n  -----  Reject set of variables ",
                    paste(usevariab,collapse=", "),
                    " with p-value ", pvalue, " -----" ,sep=""))
      }
    }
  }

  # retrieve ICP set
  finalSet <- computeSetIntersection(acceptedSets, verbose = verbose)

  # testing additional set
  if(!is.null(testAdditionalSet)){

    if(any(sapply(c(rejectedSets, acceptedSets), function(i) setequal(i, testAdditionalSet)))){
      if(verbose)
        cat(paste("\n\n ----- Additional set ",
                  paste(testAdditionalSet,collapse=", "), " has already been tested ----- ",sep=""))
    }else{
      if(verbose)
        cat(paste("\n\n ----- Additionally testing variables ",
                  paste(testAdditionalSet,collapse=", "), " ----- ",sep=""))


      designMat <- X[, testAdditionalSet,drop=FALSE]

      pvalueAndDecision <- getPValueAndDecision(designMat,
                                                Y, environment,
                                                condIndTest = condIndTest,
                                                argsCondIndTest = argsCondIndTest,
                                                alpha=alpha,
                                                speedUp = speedUp,
                                                subsampleSize = subsampleSize,
                                                verbose = verbose)

      pvalue <- pvalueAndDecision$pvalue
      decision <- pvalueAndDecision$decision

      # accept is decision is 1
      if(decision == 1){

        if(verbose)
          cat(paste("\n  -----  Accepted set of variables ",
                    paste(testAdditionalSet,collapse=", "),
                    " with p-value ", pvalue, " -----" ,sep=""))


        acceptedSets[[length(acceptedSets)+1]] <- testAdditionalSet


        if(!is.null(pvalueAndDecision$model)){
          acceptedModels[[length(acceptedModels)+1]] <- pvalueAndDecision$model
        }

        pvalues.accepted <- c(pvalues.accepted, pvalue)
      }else{
        rejectedSets[[length(rejectedSets)+1]] <- testAdditionalSet
        pvalues.rejected <- c(pvalues.rejected, pvalue)

        if(verbose)
          cat(paste("\n  -----  Reject set of variables ",
                    paste(testAdditionalSet,collapse=", "),
                    " with p-value ", pvalue, " -----" ,sep=""))
      }
    }


  }

  if(verbose)
    cat(paste("\n\n  ----- Accepted sets ",
              paste(sapply(acceptedSets, function(s) paste(s, collapse = ", ")),collapse=" ;; "),  "-----" ,sep=""))

  if(verbose)
    cat(paste("\n\n  ----- Retrieved set ",
              paste(finalSet,collapse=", "),  "-----" ,sep=""))

  definingSets <-
    if(length(finalSet) == 0 & length(acceptedSets) != 0)
      computeDefiningSets(acceptedSets)
    else
      NULL

  if(!is.null(definingSets)){
    if(verbose){
      cat("\n\n  ----- Defining sets \n")
      sapply(definingSets, print)
    }
  }

  settings <- list(condIndTest = condIndTest,
                   argsCondIndTest = argsCondIndTest,
                   alpha=alpha,
                   varPreSelectionFunc = varPreSelectionFunc,
                   argsVarPreSelectionFunc = argsVarPreSelectionFunc,
                   maxSizeSets = maxSizeSets,
                   condIndTestNames = condIndTestNames,
                   speedUp = speedUp,
                   subsampleSize = subsampleSize,
                   retrieveDefiningsSets = retrieveDefiningsSets,
                   stopIfEmpty = stopIfEmpty,
                   testAdditionalSet = testAdditionalSet,
                   seed = seed)


  nonlinICP.result <- list(retrievedCausalVars = finalSet,
       acceptedSets = acceptedSets,
       definingSets = definingSets,
       acceptedModels = acceptedModels,
       pvalues.accepted = pvalues.accepted,
       rejectedSets = rejectedSets,
       pvalues.rejected = pvalues.rejected,
       settings = settings)

  class(nonlinICP.result) <- "nonlinICP.class"

  return(nonlinICP.result)
}
