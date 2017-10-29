# BLAST.R
#
# Purpose: Send off one BLAST search and return parsed list of results
#          This script uses the BLAST URL-API
#          (Application Programming Interface) at the NCBI.
#          Read about the constraints here:
#          https://ncbi.github.io/blast-cloud/dev/api.html
#
#
# Version: 2.1
# Date:    2016 09 - 2017 10
# Author:  Boris Steipe
#
# Versions:
#    2.1   bugfix in BLAST(), bug was blanking non-split deflines;
#          refactored parseBLASTalignment() to handle lists with multiple hits.
#    2.0   Completely rewritten because the interface completely changed.
#          Code adpated in part from NCBI Perl sample code:
#          $Id: web_blast.pl,v 1.10 2016/07/13 14:32:50 merezhuk Exp $
#
#    1.0   first version posted for BCH441 2016, based on BLAST - API
#
# ToDo:
#
# Notes:   This is somewhat pedestrian, but apparently there are currently
#          no R packages that contain such code.
#
# ==============================================================================


if (! require(httr, quietly = TRUE)) {
  install.packages("httr")
  library(httr)
}


BLAST <- function(q,
                  db = "refseq_protein",
                  nHits = 30,
                  E = 0.1,
                  limits = "",
                  rid = "",
                  quietly = FALSE,
                  myTimeout = 120) {
    # Purpose:
    #     Basic BLAST search
    # Version: 2.0
    # Date:    2017-09
    # Author:  Boris Steipe
    #
    # Parameters:
    #     q: query - either a valid ID or a sequence
    #     db: "refseq_protein" by default,
    #         other legal valuses include: "nr", "pdb", "swissprot" ...
    #     nHits: number of hits to maximally return
    #     E: E-value cutoff. Do not return hits whose score would be expected
    #        to occur E or more times in a database of random sequence.
    #     limits: a valid ENTREZ filter
    #     rid: a request ID - to retrieve earleir search results
    #     quietly: controls printing of wait-time progress bar
    #     timeout: how much longer _after_ rtoe to wait for a result
    #              before giving up (seconds)
    # Value:
    #     result: list of resulting hits and some metadata


    EXTRAWAIT <- 10 # duration of extra wait cycles if BLAST search is not done

    results <- list()
    results$rid <- rid
    results$rtoe <- 0

    if (rid == "") {  # if rid is not the empty string we skip the
                      # initial search and and proceed directly to retrieval


      # prepare query, GET(), and parse rid and rtoe from BLAST server response
      results$query <- paste0("https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi",
                              "?",
                              "CMD=Put",
                              "&PROGRAM=", "blastp",
                              "&QUERY=", URLencode(q),
                              "&DATABASE=", db,
                              "&MATRIX=", "BLOSUM62",
                              "&EXPECT=", as.character(E),
                              "&HITLIST_SIZE=", as.character(nHits),
                              "&ALIGNMENTS=", as.character(nHits),
                              "&FORMAT_TYPE=Text")

      if (limits != "") {
        results$query <- paste0(
          results$query,
          "&ENTREZ_QUERY=", limits)
      }

      # send it off ...
      response <- GET(results$query)
      if (http_status(response)$category != "Success" ) {
        stop(sprintf("PANIC: Can't send query. BLAST server status error: %s",
                     http_status(response)$message))
      }

      txt <- content(response, "text", encoding = "UTF-8")

      patt <- "RID = (\\w+)" # match the request id
      results$rid  <- regmatches(txt, regexec(patt,  txt))[[1]][2]

      patt <- "RTOE = (\\d+)" # match the expected completion time
      results$rtoe <- as.numeric(regmatches(txt, regexec(patt, txt))[[1]][2])

      # Now we wait ...
      if (quietly) {
        Sys.sleep(results$rtoe)
      } else {
        cat(sprintf("BLAST is processing %s:\n", results$rid))
        waitTimer(results$rtoe)
      }

    } # done sending query and retrieving rid, rtoe

    # Enter an infinite loop to check for result availability
    checkStatus <- paste("https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi",
                         "?",
                         "CMD=Get",
                         "&RID=", results$rid,
                         "&FORMAT_TYPE=Text",
                         "&FORMAT_OBJECT=SearchInfo",
                         sep = "")

    while (TRUE) {
      # Check whether the result is ready
      response <- GET(checkStatus)
      if (http_status(response)$category != "Success" ) {
        stop(sprintf("PANIC: Can't check status. BLAST server status error: %s",
                     http_status(response)$message))
      }

      txt <- content(response, "text", encoding = "UTF-8")

      if (length(grep("Status=WAITING",  txt)) > 0) {
        myTimeout <- myTimeout - EXTRAWAIT

        if (myTimeout <= 0) { # abort
          cat("BLAST search not concluded before timeout. Aborting.\n")
          cat(sprintf("You could check back later with rid \"%s\"\n",
                      results$rid))
          return(results)
        }

        if (quietly) {
          Sys.sleep(EXTRAWAIT)
        } else {
          cat(sprintf("Status: Waiting. Wait %d more seconds (max. %d more)",
                      EXTRAWAIT,
                      myTimeout))
          waitTimer(EXTRAWAIT)
          next
        }

      } else if (length(grep("Status=FAILED",  txt)) > 0) {
          cat("BLAST search returned status \"FAILED\". Aborting.\n")
          return(results)

      } else if (length(grep("Status=UNKNOWN",  txt)) > 0) {
          cat("BLAST search returned status \"UNKNOWN\".\n")
          cat("This probably means the rid has expired. Aborting.\n")
          return(results)

      } else if (length(grep("Status=READY",  txt)) > 0) {  # Done

          if (length(grep("ThereAreHits=yes",  txt)) == 0) {  # No hits
            cat("BLAST search ready but no hits found. Aborting.\n")
            return(results)

          } else {
            break  # done ... retrieve search result
          }
      }
    } # end result-check loop

    # retrieve results from BLAST server
    retrieve <- paste("https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi",
                      "?",
                      "&CMD=Get",
                      "&RID=", results$rid,
                      "&FORMAT_TYPE=Text",
                      sep = "")

    response <- GET(retrieve)
    if (http_status(response)$category != "Success" ) {
      stop(sprintf("PANIC: Can't retrieve. BLAST server status error: %s",
                   http_status(response)$message))
    }

    txt <- content(response, "text", encoding = "UTF-8")

    # txt contains the whole set of results. Process:

    # First, we strsplit() on linebreaks:
    txt <- unlist(strsplit(txt, "\n"))

    # The alignments range from the first line that begins with ">" ...
    iFirst <- grep("^>", txt)[1]

    # ... to the last line that begins with "Sbjct"
    x <- grep("^Sbjct", txt)
    iLast <- x[length(x)]

    # Get the alignments block
    txt <- txt[iFirst:iLast]

    # Drop empty lines
    txt <- txt[!(nchar(txt) == 0)]

    # A line that ends "]" but does not begin ">" seems to be a split
    # defline ... eg.
    #  [1] ">XP_013349208.1 AUEXF2481DRAFT_695809 [Aureobasidium subglaciale "
    #  [2] "EXF-2481]"
    #  Merge these lines to the preceding lines and delete them.
    #
    x <- which(grepl("]$", txt) & !(grepl("^>", txt)))
    if (length(x) > 0) {
      txt[x-1] <- paste0(txt[x-1], txt[x])
      txt <- txt[-x]
    }

    # Special case: there may be multiple deflines when the BLAST hit is to
    # redundant, identical sequences. Keep only the first instance.
    iKeep <- ! grepl("^>", txt)
    x <- rle(iKeep)
    x$positions <- cumsum(x$lengths)
    i <- which(x$lengths > 1 & x$values == FALSE)
    if (length(i) > 0) {
      firsts <- x$positions[i] - x$lengths[i] + 1
      iKeep[firsts] <- TRUE
      txt <- txt[iKeep]
    }

    # After this preprocessing the following should be true:
    # - Every alignment block begins with a defline in which the
    #   first character is ">"
    # - There is only one defline in each block.
    # - Lines are not split.

    # Make a dataframe of first and last indices of alignment blocks
    x <- grep("^>", txt)
    blocks <- data.frame(iFirst = x,
                         iLast  = c((x[-1] - 1), length(txt)))

    # Build the hits list by parsing the blocks
    results$hits <- list()

    for (i in seq_len(nrow(blocks))) {
      thisBlock <- txt[blocks$iFirst[i]:blocks$iLast[i]]
      results$hits[[i]] <- parseBLASTalignment(thisBlock)
    }

    return(results)
}

parseBLASTalignment <- function(hits, idx) {
  # Parse one BLAST hit from a BLAST result
  # Parameters:
  #    hits  list   contains the BLAST hits
  #    idx   int    index of the requested hit
  # Value:
  #          list   $def          chr   defline
  #                 $accession    chr   accession number
  #                 $organism     chr   complete organism definition
  #                 $species      chr   binomial species
  #                 $E            num   E value
  #                 $lengthAli    num   length of the alignment
  #                 $nIdentitites num   number of identities
  #                 $nGaps        num   number of gaps
  #                 $Qbounds      num   2-element vector of query start-end
  #                 $Sbounds      num   2-element vector of subject start-end
  #                 $Qseq         chr   query sequence
  #                 $midSeq       chr   midline string
  #                 $Sseq         chr   subject sequence

  h <- list()

  hit <- hits$hits[[idx]]

  # FASTA defline
  h$def <- hit$def

  # accesion number (ID), use the first if there are several, separated by "|"
  patt <- "^>(.+?)(\\s|\\|)" # from ">" to space or "|"
  h$accession <-  regmatches(h$def, regexec(patt, h$def))[[1]][2]

  # organism
  patt <- "\\[(.+)]"
  h$organism <-  regmatches(h$def, regexec(patt, h$def))[[1]][2]

  # species
  x <- unlist(strsplit(h$organism, "\\s+"))
  if (length(x) >= 2) {
    h$species <- paste(x[1], x[2])
  } else if (length(x) == 1) {
    h$species <- paste(x[1], "sp.")
  } else {
    h$species <- NA
  }

  # E-value
  h$E <-  hit$E

  # length of hit and # identities
  h$lengthAli   <- hit$lengthAli
  h$nIdentities <- hit$nIdentities

  # number of gaps
  h$nGaps <- hit$nGaps

  # first and last positions
  h$Qbounds <- hit$Qbounds
  h$Sbounds <- hit$Sbounds

  # aligned sequences

  h$Qseq   <- hit$Qseq
  h$midSeq <- hit$midSeq
  h$Sseq   <- hit$Sseq

  return(h)
}


# ==== TESTS ===================================================================

# define query:
# q   <- paste("IYSARYSGVDVYEFIHSTGSIMKRKKDDWVNATHI", # Mbp1 APSES domain sequence
#              "LKAANFAKAKRTRILEKEVLKETHEKVQGGFGKYQ",
#              "GTWVPLNIAKQLAEKFSVYDQLKPLFDFTQTDGSASP",
#              sep="")
# or ...
# q <- "NP_010227" # refseq ID
#
# test <- BLAST(q,
#               nHits = 100,
#               E = 0.001,
#               rid = "",
#               limits = "txid4751[ORGN]")
# length(test$hits)

# [END]
