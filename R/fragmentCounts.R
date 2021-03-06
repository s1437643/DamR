#' Count reads in restriction fragments
#'
#' Assign mapped sequencing reads to restriction fragments.
#'
#' @param reads A character vector of paths to BAM files.
#' @param fragments A \code{GRanges} object of restriction fragments.
#' @param mode Read counting mode. Can be either "inner" or "flank".
#' @return A \code{RangedSummarizedExperiment} object.

fragmentCounts <- function(reads, fragments, mode = c("inner", "flank")) {

    # Check argument missing
    if (missing(reads)) {
        stop("`reads` is missing, with no default.", call. = FALSE)
    }
    if (missing(fragments)) {
        stop("`fragments` is missing, with no default.", call. = FALSE)
    }

    # Check argument class
    if (!is(reads, "character")) {
        stop("`reads` must be a character vector.", call. = FALSE)
    }
    if (!is(fragments, "GRanges")) {
        stop("`fragments` must be a GRanges object.", call. = FALSE)
    }

    # Check BAM files exist
    bamExists <- file.exists(reads)
    if (!all(bamExists)) {
        text <- paste("*", reads[!bamExists], collapse = "\n")
        stop("Each file in `reads` must exist:\n", text, call. = FALSE)
    }

    # Index required BAM files
    baiPaths <- paste0(reads, ".bai")
    baiExists <- file.exists(baiPaths)
    if (!all(baiExists)) {
        indexBam(reads[!baiExists])
    }

    # Check counting mode is valid
    countMode <- match.arg(mode)

    # Dispatch relevant method
    if (countMode == "inner") {
        fragmentCounts.inner(reads, fragments)
    } else if (countMode == "flank") {
        fragmentCounts.flank(reads, fragments)
    } else {
        stop('`mode` should be one of "inner" or "flank".', call. = FALSE)
    }

}

fragmentCounts.inner <- function(reads, fragments) {

    # Extract fragment ranges
    featureRanges <- granges(fragments)
    mcols(featureRanges)$id <- seq_along(featureRanges)

    # Create annotation file
    annotFile <- data.frame(
        GeneID = featureRanges$id,
        Chr = seqnames(featureRanges),
        Start = start(featureRanges),
        End = end(featureRanges),
        Strand = "+"
    )

    # Count reads into fragments
    invisible(utils::capture.output(featureCounts <- Rsubread::featureCounts(
        files = reads,
        annot.ext = annotFile,
        read2pos = 5,
        ignoreDup = TRUE
    )))

    # Create experiment data
    assaysData <- list(countsData = unname(featureCounts$counts))
    rangesData <- fragments
    sampleData <- DataFrame(bamPath = reads)

    # Combine experiment data
    rawData <- SummarizedExperiment(
        assays = assaysData,
        rowRanges = rangesData,
        colData = sampleData
    )

    # Return experiment data
    rawData
}

fragmentCounts.flank <- function(reads, fragments) {

    # Extract fragment ranges
    restFrags <- granges(fragments)

    # Define flank size
    flankSize <- 100

    # Extract flanking regions
    restSite5 <- resize(restFrags, width = flankSize, fix = "start")
    restSite3 <- resize(restFrags, width = flankSize, fix = "end")

    # Restrict flanking regions
    restSite5 <- restrict(restSite5, start = start(restFrags), end = end(restFrags))
    restSite3 <- restrict(restSite3, start = start(restFrags), end = end(restFrags))

    # Combine flanking regions
    restSites <- c(restSite5, restSite3)[order(c(seq_along(restSite5), seq_along(restSite3)))]

    # Rename flanking regions
    mcols(restSites)$id <- rep(seq_along(restFrags), each = 2)

    # Create annotation file
    annotFile <- data.frame(
        GeneID = restSites$id,
        Chr = seqnames(restSites),
        Start = start(restSites),
        End = end(restSites),
        Strand = "+"
    )

    # Count reads into fragments
    invisible(utils::capture.output(featureCounts <- Rsubread::featureCounts(
        files = reads,
        annot.ext = annotFile,
        useMetaFeatures = TRUE,
        read2pos = 5,
        ignoreDup = TRUE
    )))

    # Create experiment data
    assaysData <- list(countsData = unname(featureCounts$counts))
    rangesData <- fragments
    sampleData <- DataFrame(bamPath = reads)

    # Combine experiment data
    rawData <- SummarizedExperiment(
        assays = assaysData,
        rowRanges = rangesData,
        colData = sampleData
    )

    # Return experiment data
    rawData
}
