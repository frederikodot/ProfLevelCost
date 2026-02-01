# Makefile
# Creates a CurseForge/WowUp-friendly release zip for the split addon structure.
#
# Key requirement: the ZIP must contain addon folders at the ROOT of the archive,
# e.g.:
#   ProfLevelCost/
#   ProfLevelCost_Data_AL/
#   ProfLevelCost_Data_BS/
#   ...
#
# Usage:
#   make zip
#   make zip VERSION=1.2.3
#   make clean

SHELL := /bin/bash

NAME_PREFIX ?= ProfLevelCost
CORE_DIR ?= ProfLevelCost
DATA_DIRS := $(wildcard ProfLevelCost_Data_*)
ADDON_DIRS := $(CORE_DIR) $(DATA_DIRS)

# Prefer git tag/describe for version, otherwise timestamp.
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || date +%Y%m%d_%H%M)
DIST_DIR ?= dist
ZIP_NAME := $(DIST_DIR)/$(NAME_PREFIX)-$(VERSION).zip

.PHONY: zip check clean

check:
	@set -e; \
	if [ ! -d "$(CORE_DIR)" ]; then \
	  echo "ERROR: missing core addon folder '$(CORE_DIR)'."; \
	  echo "Expected a folder named '$(CORE_DIR)' at the repo root."; \
	  exit 1; \
	fi; \
	if [ -z "$(DATA_DIRS)" ]; then \
	  echo "WARNING: no data modules found matching 'ProfLevelCost_Data_*'."; \
	  echo "If you split pools into LOD addons, ensure those folders exist at the repo root."; \
	fi; \
	echo "Addon folders to package:"; \
	for d in $(ADDON_DIRS); do echo "  - $$d"; done

zip: check
	@set -e; \
	mkdir -p "$(DIST_DIR)"; \
	rm -f "$(ZIP_NAME)"; \
	echo "Creating $(ZIP_NAME) ..."; \
	zip -9 -r "$(ZIP_NAME)" $(ADDON_DIRS) \
	  -x "**/.git/*" "**/.git/**" \
	  -x ".git/*" ".git/**" \
	  -x ".gitignore" ".gitattributes" ".gitmodules" \
	  -x "**/.gitignore" "**/.gitattributes" "**/.gitmodules" \
	  -x "$(DIST_DIR)/*" "$(DIST_DIR)/**" \
	  -x "*.zip" \
	  -x "Makefile" \
	  -x "**/.DS_Store" "**/Thumbs.db" \
	  -x "**/*~" "**/*.swp" "**/*.tmp"; \
	echo "Done: $(ZIP_NAME)"; \
	echo ""; \
	echo "ZIP top-level folders:"; \
	unzip -Z1 "$(ZIP_NAME)" | awk -F/ 'NF>1{print $$1}' | sort -u | sed 's/^/  - /'

clean:
	@echo "Cleaning $(DIST_DIR) ..."
	@rm -rf "$(DIST_DIR)"
	@echo "Done."
