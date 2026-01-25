# Makefile
# Creates a timestamped zip of the current folder, excluding any git-related files.
# Usage:
#   make zip
#   make zip NAME_PREFIX=ProfLevelCost

SHELL := /bin/bash

NAME_PREFIX ?= ProfLevelCost
DATE := $(shell date +%Y%m%d_%H%M)
ZIP_NAME := $(NAME_PREFIX)_$(DATE).zip

.PHONY: zip
zip:
	@echo "Creating $(ZIP_NAME)..."
	@rm -f "$(ZIP_NAME)"
	@zip -r "$(ZIP_NAME)" . \
		-x ".git/*" ".git/**" \
		-x ".gitignore" ".gitattributes" ".gitmodules" \
		-x "**/.git/*" "**/.git/**" \
		-x "**/.gitignore" "**/.gitattributes" "**/.gitmodules" \
		-x "*.zip" \
		-x "Makefile" 
	@echo "Done: $(ZIP_NAME)"

clean:
	@echo "Removing zip files..."
	@rm -f ./*.zip
	@echo "Done."
