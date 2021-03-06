# tocID <- "RPR-UniProt_GET.R"
#
# Purpose:  A Bioinformatics Course:
#              R code accompanying the RPR-Scripting_data_downloads unit.
#
# Version:  1.2
#
# Date:     2017-10  -  2020-09
# Author:   Boris Steipe (boris.steipe@utoronto.ca)
#
# Versions:
#           1.2    2020 Maintenance. Made dbFetchUniProtSeq() vector-safe and
#                  added FASTA headers as attribute
#           1.1    Change from require() to requireNamespace(),
#                      use <package>::<function>() idiom throughout
#           1.0    First ABC units version
#           0.1    First code copied from 2016 material.
#
#
# TODO:
#
#
# == DO NOT SIMPLY  source()  THIS FILE! =======================================
#
# If there are portions you don't understand, use R's help system, Google for an
# answer, or ask your instructor. Don't continue if you don't understand what's
# going on. That's not how it works ...
#
# ==============================================================================


#TOC> ==========================================================================
#TOC> 
#TOC>   Section  Title                                      Line
#TOC> ----------------------------------------------------------
#TOC>   1        UniProt files via GET                        43
#TOC>   1.1        Task - fetchUniProtSeq() function         105
#TOC>   2        Task solutions                              118
#TOC> 
#TOC> ==========================================================================


# =    1  UniProt files via GET  ===============================================


# Perhaps the simplest example of scripted download is to retrieve a protein
# FASTA sequence from UniProt. All we need is to construct an URL with the
# correct UniProt ID.

# An interface between R scripts and Web servers is provided by the httr::
# package. This sends and receives information via the http protocol, just like
# a Web browser. Since this is a short and simple request, the GET verb is the
# right tool:

if (! requireNamespace("httr", quietly = TRUE)) {
  install.packages("httr")
}
# Package information:
#  library(help = httr)       # basic information
#  browseVignettes("httr")    # available vignettes
#  data(package = "httr")     # available datasets


# The UniProt ID for Mbp1 is ...

UniProtID <- "P39678"

# and the base URL to retrieve data is  ...
# http://www.uniprot.org/uniprot/ . We can construct a simple URL to
# retrieve a FASTA sequence:

(URL <- sprintf("http://www.uniprot.org/uniprot/%s.fasta", UniProtID))

# the GET() function from httr will get the data.
response <- httr::GET(URL)

str(response) # the response object is a bit complex ...
as.character(response) # ... but it is easy to pull out the data.

# to process  ...
x <- as.character(response)
x <- strsplit(x, "\n")
dbSanitizeSequence(x)

# Simple.
# But what happens if there is an error, e.g. the uniprot ID does not exist?

response <- httr::GET("http://www.uniprot.org/uniprot/X000000.fasta")
as.character(response)
# this is a large HTML page that tells us the URL was not found. So we need to
# check for errors.  The Right Way to do this is to evaluate the staus code that
# every Web server returns for every transaction.
#
httr::status_code(response)  # 404 == Page Not Found

# There are many possible codes, but the only code we will be happy with
# is 200 - oK.
# (cf. https://en.wikipedia.org/wiki/List_of_HTTP_status_codes )

URL <- sprintf("http://www.uniprot.org/uniprot/%s.fasta", UniProtID)
response <- httr::GET(URL)
httr::status_code(response)


# ==   1.1  Task - fetchUniProtSeq() function  =================================

# Task: write a function that
#   - takes as input a vector of UniProt IDs,
#   - fetches the FASTA sequence for each
#   - returns a vector of the same length as the input, where an element is:
#   -  ...  the sequence, if the query was successful
#   -  ...  NA if there was an error
#   - each element has the UniProt ID as the name()
#   - bonus: the output has an attribute "headers" that is a vector of the
#            FASTA headers ( cf. ?attr )


# =    2  Task solutions  ======================================================


# I have placed such a function - dbFetchUniProtSeq() - into
# "./scripts/ABC-dbUtilities.R": look it up by clicking on  dbFetchUniProtSeq()
# in the Environment pane.

# Test this:
( x <- dbFetchUniProtSeq("P39678") )
names(x)[1]
attr(x, "headers")[1]
x[1]
cat(writeFASTA(data.frame(head = attr(x, "headers")[1], seq  =x[1]),
               width = 40), sep = "\n")



# [END]
