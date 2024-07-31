############################################################
############################################################
# vcov.gamlss() function 
# 
# Modefied by: Mikis Stasinopoulos
# 
############################################################
############################################################
vcov.gamlss <- function (object, 
                           type = c("vcov", "cor", "se", "coef", "all"),
                         robust = FALSE, 
                    hessian.fun = c("R", "PB"),   
                ...) 
{
  HessianPB<-function (pars, fun, ..., .relStep = (.Machine$double.eps)^(1/3), 
                       minAbsPar = 0) 
  {
    pars <- as.numeric(pars)
    npar <- length(pars)
    incr <- ifelse(abs(pars) <= minAbsPar, minAbsPar * .relStep, 
                   abs(pars) * .relStep)
    baseInd <- diag(npar)
    frac <- c(1, incr, incr^2)
    cols <- list(0, baseInd, -baseInd)
    for (i in seq_along(pars)[-npar]) {
      cols <- c(cols, list(baseInd[, i] + baseInd[, -(1:i)]))
      frac <- c(frac, incr[i] * incr[-(1:i)])
    }
    indMat <- do.call("cbind", cols)
    shifted <- pars + incr * indMat
    indMat <- t(indMat)
    Xcols <- list(1, indMat, indMat^2)
    for (i in seq_along(pars)[-npar]) {
      Xcols <- c(Xcols, list(indMat[, i] * indMat[, -(1:i)]))
    }
    coefs <- solve(do.call("cbind", Xcols), apply(shifted, 2, 
                                                  fun, ...))/frac
    Hess <- diag(coefs[1 + npar + seq_along(pars)], ncol = npar)
    Hess[row(Hess) > col(Hess)] <- coefs[-(1:(1 + 2 * npar))]
    list(mean = coefs[1], gradient = coefs[1 + seq_along(pars)], 
         
         Hessian = (Hess + t(Hess)))
  }  
  
       type <- match.arg(type)
hessian.fun <- match.arg(hessian.fun)
  if (!is.gamlss(object)) 
     stop(paste("This is not an gamlss object", "\n", ""))
  coefBeta <- list()
  for (i in object$par) 
  {
    if (i == "mu") 
      {
      if (!is.null(unlist(attr(terms(formula(object), specials = .gamlss.sm.list), 
                               "specials")))) 
        warning("addive terms exists in the mu formula standard errors for the linear terms maybe are not appropriate")
    }
    else 
    {
      if (!is.null(formula(object, i)) && !is.null(unlist(attr(terms(formula(object, i), 
                                     specials = .gamlss.sm.list), "specials")))) 
        warning(paste("addive terms exists in the ", 
                      i, " formula standard errors for the linear terms maybe are not appropriate"))
    }
    nonNAcoef <- !is.na(coef(object, i))
     coefBeta <- c(coefBeta, coef(object, i)[nonNAcoef])
  }
   betaCoef <- unlist(coefBeta)      
   like.fun <- gen.likelihood(object)
       hess <- if (hessian.fun=="R" ) optimHess(betaCoef, like.fun)
               else HessianPB(betaCoef, like.fun)$Hessian
     varCov <- try(solve(hess), silent = TRUE)
      if (any(class(varCov)%in%"try-error"))
        {
        varCov <- try(solve(HessianPB(betaCoef, like.fun)$Hessian), silent = TRUE) 
        if (any(class(varCov)%in%"try-error"))
        stop("the Hessian matrix is singular probably the model is overparametrised")
        }
         se <- sqrt(diag(varCov))
   coefBeta <- unlist(coefBeta)
    if (robust)
    {
      K <- get.K(object)
      varCov <- varCov%*%K%*%varCov
      se <- sqrt(diag(varCov))
      corr <- cov2cor(varCov)
    }
  switch(type, vcov = varCov, cor = corr, se = se, coef = coefBeta, 
         all = list(coef = coefBeta, se = se, vcov = varCov, 
                    cor = corr))
}