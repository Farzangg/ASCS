############################################################
############################################################
# Modification of brstep function
# 
# Modified by: Shinsuke Ohnuki
# 
############################################################
############################################################

brstep <- function (object, scope, scale = 0, direction = c("both", "backward", "forward"), 
                    trace = 1, keep = NULL, steps = 1000, k = 2, ...) 
{
  mydeviance <- function(x, ...) {
    dev <- deviance(x)
    if (!is.null(dev)) 
      dev
    else extractAIC(x, k = 0)[2L]
  }
  cut.string <- function(string) {
    if (length(string) > 1L) 
      string[-1L] <- paste0("\n", string[-1L])
    string
  }
  re.arrange <- function(keep) {
    namr <- names(k1 <- keep[[1L]])
    namc <- names(keep)
    nc <- length(keep)
    nr <- length(k1)
    array(unlist(keep, recursive = FALSE), c(nr, nc), list(namr, namc))
  }
  step.results <- function(models, fit, object, usingCp = FALSE) {
    change <- sapply(models, "[[", "change")
    rd <- sapply(models, "[[", "deviance")
    dd <- c(NA, abs(diff(rd)))
    rdf <- sapply(models, "[[", "df.resid")
    ddf <- c(NA, diff(rdf))
    AIC <- sapply(models, "[[", "AIC")
    heading <- c("Stepwise Model Path \nAnalysis of Deviance Table", 
                 "\nInitial Model:", deparse(formula(object)), "\nFinal Model:", 
                 deparse(formula(fit)), "\n")
    aod <- data.frame(Step = I(change), Df = ddf, Deviance = dd, 
                      `Resid. Df` = rdf, `Resid. Dev` = rd, AIC = AIC, 
                      check.names = FALSE)
    if (usingCp) {
      cn <- colnames(aod)
      cn[cn == "AIC"] <- "Cp"
      colnames(aod) <- cn
    }
    attr(aod, "heading") <- heading
    fit$anova <- aod
    fit
  }
  ### add1.brglm
  add1.brglm <- function (object, scope, scale = 0,
                          test = c("none", "Rao", "LRT", "Chisq", "F"),
                          x = NULL, k = 2, ...) 
  {
    Fstat <- function(table, rdf) {
      dev <- table$Deviance
      df <- table$Df
      diff <- pmax(0, (dev[1L] - dev)/df)
      Fs <- diff/(dev/(rdf - df))
      Fs[df < .Machine$double.eps] <- NA
      P <- Fs
      nnas <- !is.na(Fs)
      P[nnas] <- safe_pf(Fs[nnas], df[nnas], rdf - df[nnas], 
                         lower.tail = FALSE)
      list(Fs = Fs, P = P)
    }
    test <- match.arg(test)
    if (test == "Chisq") 
      test <- "LRT"
    if (!is.character(scope)) 
      scope <- add.scope(object, update.formula(object, scope))
    if (!length(scope)) 
      stop("no terms in scope for adding to object")
    oTerms <- attr(object$terms, "term.labels")
    int <- attr(object$terms, "intercept")
    ns <- length(scope)
    dfs <- dev <- score <- numeric(ns + 1)
    names(dfs) <- names(dev) <- names(score) <- c("<none>", 
                                                  scope)
    add.rhs <- paste(scope, collapse = "+")
    add.rhs <- eval(parse(text = paste("~ . +", add.rhs)))
    new.form <- update.formula(object, add.rhs)
    Terms <- terms(new.form)
    y <- object$y
    if (is.null(x)) {
      fc <- object$call
      fc$formula <- Terms
      fob <- list(call = fc, terms = Terms)
      class(fob) <- oldClass(object)
      m <- model.frame(fob, xlev = object$xlevels)
      offset <- model.offset(m)
      wt <- model.weights(m)
      x <- model.matrix(Terms, m, contrasts.arg = object$contrasts)
      oldn <- length(y)
      y <- model.response(m)
      if (!is.factor(y)) 
        storage.mode(y) <- "double"
      if (NCOL(y) == 2) {
        n <- y[, 1] + y[, 2]
        y <- ifelse(n == 0, 0, y[, 1]/n)
        if (is.null(wt)) 
          wt <- rep.int(1, length(y))
        wt <- wt * n
      }
      newn <- length(y)
      if (newn < oldn) 
        warning(sprintf(ngettext(newn, "using the %d/%d row from a combined fit", 
                                 "using the %d/%d rows from a combined fit"), 
                        newn, oldn), domain = NA)
    }
    else {
      wt <- object$prior.weights
      offset <- object$offset
    }
    n <- nrow(x)
    if (is.null(wt)) 
      wt <- rep.int(1, n)
    Terms <- attr(Terms, "term.labels")
    asgn <- attr(x, "assign")
    ousex <- match(asgn, match(oTerms, Terms), 0L) > 0L
    if (int) 
      ousex[1L] <- TRUE
    X <- x[, ousex, drop = FALSE]
    z <- brglm.fit(X, y, wt, offset = offset, family = object$family, 
                   control = object$control.glm, control.brglm = object$control.brglm)
    dfs[1L] <- z$rank
    dev[1L] <- z$deviance
    r <- z$residuals
    w <- z$weights
    sTerms <- sapply(strsplit(Terms, ":", fixed = TRUE), function(x) paste(sort(x), 
                                                                           collapse = ":"))
    for (tt in scope) {
      stt <- paste(sort(strsplit(tt, ":")[[1L]]), collapse = ":")
      usex <- match(asgn, match(stt, sTerms), 0L) > 0L
      X <- x[, usex | ousex, drop = FALSE]
      z <- brglm.fit(X, y, wt, offset = offset, family = object$family, 
                     control = object$control.glm, control.brglm = object$control.brglm)
      dfs[tt] <- z$rank
      dev[tt] <- z$deviance
      if (test == "Rao") {
        zz <- brglm.fit(X, r, w, offset = offset)
        score[tt] <- zz$null.deviance - zz$deviance
      }
    }
    if (scale == 0) 
      dispersion <- summary(object, dispersion = NULL)$dispersion
    else dispersion <- scale
    fam <- object$family$family
    if (fam == "gaussian") {
      if (scale > 0) 
        loglik <- dev/scale - n
      else loglik <- n * log(dev/n)
    }
    else loglik <- dev/dispersion
    aic <- loglik + k * dfs
    aic <- aic + (extractAIC(object, k = k)[2L] - aic[1L])
    dfs <- dfs - dfs[1L]
    dfs[1L] <- NA
    aod <- data.frame(Df = dfs, Deviance = dev, AIC = aic, row.names = names(dfs), 
                      check.names = FALSE)
    if (all(is.na(aic))) 
      aod <- aod[, -3]
    test <- match.arg(test)
    if (test == "LRT") {
      dev <- pmax(0, loglik[1L] - loglik)
      dev[1L] <- NA
      LRT <- if (dispersion == 1) 
        "LRT"
      else "scaled dev."
      aod[, LRT] <- dev
      nas <- !is.na(dev)
      dev[nas] <- safe_pchisq(dev[nas], aod$Df[nas], lower.tail = FALSE)
      aod[, "Pr(>Chi)"] <- dev
    }
    else if (test == "Rao") {
      dev <- pmax(0, score)
      dev[1L] <- NA
      nas <- !is.na(dev)
      SC <- if (dispersion == 1) 
        "Rao score"
      else "scaled Rao sc."
      dev <- dev/dispersion
      aod[, SC] <- dev
      dev[nas] <- safe_pchisq(dev[nas], aod$Df[nas], lower.tail = FALSE)
      aod[, "Pr(>Chi)"] <- dev
    }
    else if (test == "F") {
      if (fam == "binomial" || fam == "poisson") 
        warning(gettextf("F test assumes quasi%s family", 
                         fam), domain = NA)
      rdf <- object$df.residual
      aod[, c("F value", "Pr(>F)")] <- Fstat(aod, rdf)
    }
    head <- c("Single term additions", "\nModel:", deparse(formula(object)), 
              if (scale > 0) paste("\nscale: ", format(scale), "\n"))
    class(aod) <- c("anova", "data.frame")
    attr(aod, "heading") <- head
    aod
  }
  ################################# End of add1.brglm
  ### drop1.brglm
  drop1.brglm <- function (object, scope, scale = 0, test = c("none", "Rao", "LRT", 
                                                              "Chisq", "F"), k = 2, ...) 
  {
    test <- match.arg(test)
    if (test == "Chisq") 
      test <- "LRT"
    x <- model.matrix(object)
    n <- nrow(x)
    asgn <- attr(x, "assign")
    tl <- attr(object$terms, "term.labels")
    if (missing(scope)) 
      scope <- drop.scope(object)
    else {
      if (!is.character(scope)) 
        scope <- attr(terms(update.formula(object, scope)), 
                      "term.labels")
      if (!all(match(scope, tl, 0L) > 0L)) 
        stop("scope is not a subset of term labels")
    }
    ndrop <- match(scope, tl)
    ns <- length(scope)
    rdf <- object$df.residual
    chisq <- object$deviance
    dfs <- numeric(ns)
    dev <- numeric(ns)
    score <- numeric(ns)
    y <- object$y
    if (is.null(y)) {
      y <- model.response(model.frame(object))
      if (!is.factor(y)) 
        storage.mode(y) <- "double"
    }
    wt <- object$prior.weights
    if (is.null(wt)) 
      wt <- rep.int(1, n)
    for (i in seq_len(ns)) {
      ii <- seq_along(asgn)[asgn == ndrop[i]]
      jj <- setdiff(seq(ncol(x)), ii)
      z <- brglm.fit(x[, jj, drop = FALSE], y, wt, offset = object$offset, family = object$family,
                     control = object$control.glm, control.brglm = object$control.brglm)
      dfs[i] <- z$rank
      dev[i] <- z$deviance
      if (test == "Rao") {
        r <- z$residuals
        w <- z$weights
        zz <- brglm.fit(x, r, w, offset = object$offset)
        score[i] <- zz$null.deviance - zz$deviance
      }
    }
    scope <- c("<none>", scope)
    dfs <- c(object$rank, dfs)
    dev <- c(chisq, dev)
    if (test == "Rao") {
      score <- c(NA, score)
    }
    dispersion <- if (is.null(scale) || scale == 0) 
      summary(object, dispersion = NULL)$dispersion
    else scale
    fam <- object$family$family
    loglik <- if (fam == "gaussian") {
      if (scale > 0) 
        dev/scale - n
      else n * log(dev/n)
    }
    else dev/dispersion
    aic <- loglik + k * dfs
    dfs <- dfs[1L] - dfs
    dfs[1L] <- NA
    aic <- aic + (extractAIC(object, k = k)[2L] - aic[1L])
    aod <- data.frame(Df = dfs, Deviance = dev, AIC = aic, row.names = scope, 
                      check.names = FALSE)
    if (all(is.na(aic))) 
      aod <- aod[, -3]
    if (test == "LRT") {
      dev <- pmax(0, loglik - loglik[1L])
      dev[1L] <- NA
      nas <- !is.na(dev)
      LRT <- if (dispersion == 1) 
        "LRT"
      else "scaled dev."
      aod[, LRT] <- dev
      dev[nas] <- safe_pchisq(dev[nas], aod$Df[nas], lower.tail = FALSE)
      aod[, "Pr(>Chi)"] <- dev
    }
    else if (test == "Rao") {
      dev <- pmax(0, score)
      nas <- !is.na(dev)
      SC <- if (dispersion == 1) 
        "Rao score"
      else "scaled Rao sc."
      dev <- dev/dispersion
      aod[, SC] <- dev
      dev[nas] <- safe_pchisq(dev[nas], aod$Df[nas], lower.tail = FALSE)
      aod[, "Pr(>Chi)"] <- dev
    }
    else if (test == "F") {
      if (fam == "binomial" || fam == "poisson") 
        warning(gettextf("F test assumes 'quasi%s' family", 
                         fam), domain = NA)
      dev <- aod$Deviance
      rms <- dev[1L]/rdf
      dev <- pmax(0, dev - dev[1L])
      dfs <- aod$Df
      rdf <- object$df.residual
      Fs <- (dev/dfs)/rms
      Fs[dfs < 1e-04] <- NA
      P <- Fs
      nas <- !is.na(Fs)
      P[nas] <- safe_pf(Fs[nas], dfs[nas], rdf, lower.tail = FALSE)
      aod[, c("F value", "Pr(>F)")] <- list(Fs, P)
    }
    head <- c("Single term deletions", "\nModel:", deparse(formula(object)), 
              if (!is.null(scale) && scale > 0) paste("\nscale: ", 
                                                      format(scale), "\n"))
    class(aod) <- c("anova", "data.frame")
    attr(aod, "heading") <- head
    aod
  }
  ################################# End of drop
  Terms <- terms(object)
  object$call$formula <- object$formula <- Terms
  md <- missing(direction)
  direction <- match.arg(direction)
  backward <- direction == "both" | direction == "backward"
  forward <- direction == "both" | direction == "forward"
  if (missing(scope)) {
    fdrop <- numeric()
    fadd <- attr(Terms, "factors")
    if (md) 
      forward <- FALSE
  }
  else {
    if (is.list(scope)) {
      fdrop <- if (!is.null(fdrop <- scope$lower)) 
        attr(terms(update.formula(object, fdrop)), "factors")
      else numeric()
      fadd <- if (!is.null(fadd <- scope$upper)) 
        attr(terms(update.formula(object, fadd)), "factors")
    }
    else {
      fadd <- if (!is.null(fadd <- scope)) 
        attr(terms(update.formula(object, scope)), "factors")
      fdrop <- numeric()
    }
  }
  models <- vector("list", steps)
  if (!is.null(keep)) 
    keep.list <- vector("list", steps)
  n <- nobs(object, use.fallback = TRUE)
  fit <- object
  bAIC <- extractAIC(fit, scale, k = k, ...)
  edf <- bAIC[1L]
  bAIC <- bAIC[2L]
  if (is.na(bAIC)) 
    stop("AIC is not defined for this model, so 'step' cannot proceed")
  if (bAIC == -Inf) 
    stop("AIC is -infinity for this model, so 'step' cannot proceed")
  nm <- 1
  if (trace) {
    cat("Start:  AIC=", format(round(bAIC, 2)), "\n", cut.string(deparse(formula(fit))), 
        "\n\n", sep = "")
    utils::flush.console()
  }
  models[[nm]] <- list(deviance = mydeviance(fit), df.resid = n - 
                         edf, change = "", AIC = bAIC)
  if (!is.null(keep)) 
    keep.list[[nm]] <- keep(fit, bAIC)
  usingCp <- FALSE
  while (steps > 0) {
    steps <- steps - 1
    AIC <- bAIC
    ffac <- attr(Terms, "factors")
    scope <- factor.scope(ffac, list(add = fadd, drop = fdrop))
    aod <- NULL
    change <- NULL
    if (backward && length(scope$drop)) {
      aod <- drop1(fit, scope$drop, scale = scale, trace = trace, 
                   k = k, ...)
      rn <- row.names(aod)
      row.names(aod) <- c(rn[1L], paste("-", rn[-1L], sep = " "))
      if (any(aod$Df == 0, na.rm = TRUE)) {
        zdf <- aod$Df == 0 & !is.na(aod$Df)
        change <- rev(rownames(aod)[zdf])[1L]
      }
    }
    if (is.null(change)) {
      if (forward && length(scope$add)) {
        aodf <- add1.brglm(fit, scope$add, scale = scale, trace = trace, k = k, ...)
        rn <- row.names(aodf)
        row.names(aodf) <- c(rn[1L], paste("+", rn[-1L], sep = " "))
        aod <- if (is.null(aod)) aodf else rbind(aod, aodf[-1, , drop = FALSE])
      }
      attr(aod, "heading") <- NULL
      nzdf <- if (!is.null(aod$Df)) 
        aod$Df != 0 | is.na(aod$Df)
      aod <- aod[nzdf, ]
      if (is.null(aod) || ncol(aod) == 0) 
        break
      nc <- match(c("Cp", "AIC"), names(aod))
      nc <- nc[!is.na(nc)][1L]
      o <- order(aod[, nc])
      if (trace) 
        print(aod[o, ])
      if (o[1L] == 1) 
        break
      change <- rownames(aod)[o[1L]]
    }
    usingCp <- match("Cp", names(aod), 0L) > 0L
    fit <- update(fit, paste("~ .", change), evaluate = FALSE)
    fit <- eval.parent(fit)
    nnew <- nobs(fit, use.fallback = TRUE)
    if (all(is.finite(c(n, nnew))) && nnew != n) 
      stop("number of rows in use has changed: remove missing values?")
    Terms <- terms(fit)
    bAIC <- extractAIC(fit, scale, k = k, ...)
    edf <- bAIC[1L]
    bAIC <- bAIC[2L]
    if (trace) {
      cat("\nStep:  AIC=", format(round(bAIC, 2)), "\n", 
          cut.string(deparse(formula(fit))), "\n\n", sep = "")
      utils::flush.console()
    }
    if (bAIC >= AIC + 1e-07) 
      break
    nm <- nm + 1
    models[[nm]] <- list(deviance = mydeviance(fit), df.resid = n - 
                           edf, change = change, AIC = bAIC)
    if (!is.null(keep)) 
      keep.list[[nm]] <- keep(fit, bAIC)
  }
  if (!is.null(keep)) 
    fit$keep <- re.arrange(keep.list[seq(nm)])
  step.results(models = models[seq(nm)], fit, object, usingCp)
}