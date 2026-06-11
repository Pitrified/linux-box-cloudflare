# makefile

## overview

a makefile for

1. serving locally to develop and test the site
2. calling a script to autogenerate a sitemap.md file with all the pages clickable pointing at actual github.io links, to quickly check for broken links and to have a single page with all the links for easy browsing
3. help target, which reads all `##` comments after each make target and prints them out as a help message, so we can have self-documenting make targets (with pretty colors!)
