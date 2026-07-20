# ==============================================================================
# HOW TO USE THIS MAKEFILE
# ==============================================================================
# This Makefile automates the build, packaging, and upload of the 
# otel-collector BOSH release to Stackit Object Storage using s3cmd.
#
# Prerequisites:
#   - go (to build binaries)
#   - tar (for packaging)
#   - s3cmd (for Object Storage upload)
#   - jq (to parse SECRETS.json)
#
# Commands:
#   make all                      - Complete pipeline: Build -> Package -> Push
#   make build                    - Only builds the binaries
#   make package                  - Only packages the release into a .tgz file
#   make push                     - Packages (if needed) and uploads to Stackit
#   make clean                    - Removes local .tgz artifacts
#
# Configuration Overrides:
#   By default, this Makefile reads credentials and bucket names from SECRETS.json.
#   You can override any of these from the command line:
#   STACKIT_BUCKET       - The target bucket name
#   STACKIT_ENDPOINT     - The Stackit Object Storage endpoint URL
#   STACKIT_REGION       - The region (default: us-east-1)
#   STACKIT_ACCESS_KEY   - Access Key for Stackit
#   STACKIT_SECRET_KEY   - Secret Access Key for Stackit
#   STACKIT_SESSION_TOKEN - Session Token (if applicable)
#
# Examples:
#   1. Use defaults from SECRETS.json you can find the credentials here: https://portal.stackit.cloud/secrets-manager/instances/4c9c474b-03bf-4292-9310-e37917d795ba/secrets/L3RlbXAtZXhjaGFuZ2UtZm9sZGVyL2N1c3RvbS1weGMtcmVsZWFzZS1taXNjLWJ1Y2tldC1jcmVkcw/secret-data?project=9db5fb30-2c5f-4158-ac7b-c69b65c8109a
#      make push STACKIT_ENDPOINT=https://object.storage.eu01.onstackit.cloud
#
#   2. Providing overrides (CI/CD):
#      make push STACKIT_BUCKET=my-bucket STACKIT_ENDPOINT=https://... STACKIT_ACCESS_KEY=...
# ==============================================================================

# --- Configuration ---
RELEASE_NAME := otel-collector
RELEASE_VERSION := $(shell grep '^[[:space:]]*version:' src/otel-collector-builder/config.yaml | awk '{print $$2}')-scf
RELEASE_TIMESTAMP_VERSION := $(RELEASE_VERSION)-$(shell date +%s)

# Read defaults from SECRETS.json using jq, but allow CLI overrides
STACKIT_BUCKET ?= $(shell jq -re '.bucket_name' SECRETS.json)
STACKIT_ENDPOINT ?= https://object.storage.eu01.onstackit.cloud
STACKIT_REGION ?= us-east-1

# --- Credentials ---
STACKIT_ACCESS_KEY ?= $(shell jq -re '.access_key' SECRETS.json)
STACKIT_SECRET_KEY ?= $(shell jq -re '.secret_key' SECRETS.json)
STACKIT_SESSION_TOKEN ?= 

# Paths & Filenames
# Convention: otel-collector/otel-collector-release-VERSION.tgz
S3_OBJECT_PATH := $(RELEASE_NAME)/otel-collector-release-$(RELEASE_VERSION).tgz
PACKAGE_FILE := otel-collector-release-$(RELEASE_VERSION).tgz

S3_OBJECT_PATH_TIMESTAMP := $(RELEASE_NAME)/otel-collector-release-$(RELEASE_TIMESTAMP_VERSION).tgz
PACKAGE_FILE_TIMESTAMP := otel-collector-release-$(RELEASE_TIMESTAMP_VERSION).tgz

S3_CONFIG := .temp_s3cfg

# --- Targets ---

.PHONY: all package push clean

all: package push

## Package the BOSH release using bosh-cli (Dev/Timestamped)
package:
	@echo 'Packaging BOSH dev release as $(PACKAGE_FILE_TIMESTAMP)...'
	bosh create-release --force --version=$(RELEASE_TIMESTAMP_VERSION) --tarball=$(PACKAGE_FILE_TIMESTAMP)

## Push the timestamped release to Stackit Object Storage
push: package
	@echo 'Generating temporary s3cmd configuration...'
	@echo '[default]' > $(S3_CONFIG)
	@echo 'access_key = $(STACKIT_ACCESS_KEY)' >> $(S3_CONFIG)
	@echo 'secret_key = $(STACKIT_SECRET_KEY)' >> $(S3_CONFIG)
	@echo 'host_base = $(STACKIT_ENDPOINT)' >> $(S3_CONFIG)
	@echo 'host_bucket = %({bucket})s.$(STACKIT_ENDPOINT)' >> $(S3_CONFIG)
	@echo 'use_https = True' >> $(S3_CONFIG)

	@echo 'Pushing timestamped release to s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH_TIMESTAMP)...'
	s3cmd put -c $(S3_CONFIG) $(PACKAGE_FILE_TIMESTAMP) s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH_TIMESTAMP)

	@rm -f $(S3_CONFIG)
	@echo 'Upload complete: s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH_TIMESTAMP)'
	@echo 'If you want to test the dev timestamp release with the pipeline you need to change the version regex'
	@echo 'regexp: otel-collector/otel-collector-release-(0\..*-scf-.*).tgz'

## Package the BOSH release using bosh-cli (Final)
package-final:
	@echo 'Packaging BOSH release as $(PACKAGE_FILE)...'
	bosh create-release --version=$(RELEASE_VERSION) --tarball=$(PACKAGE_FILE)

## Push the final release to Stackit Object Storage
push-final: package-final
	@echo 'Generating temporary s3cmd configuration...'
	@echo '[default]' > $(S3_CONFIG)
	@echo 'access_key = $(STACKIT_ACCESS_KEY)' >> $(S3_CONFIG)
	@echo 'secret_key = $(STACKIT_SECRET_KEY)' >> $(S3_CONFIG)
	@echo 'host_base = $(STACKIT_ENDPOINT)' >> $(S3_CONFIG)
	@echo 'host_bucket = %({bucket})s.$(STACKIT_ENDPOINT)' >> $(S3_CONFIG)
	@echo 'use_https = True' >> $(S3_CONFIG)

	@echo 'Pushing final release to s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH)...'
	s3cmd put -c $(S3_CONFIG) $(PACKAGE_FILE) s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH)

	@rm -f $(S3_CONFIG)
	@echo 'Upload complete: s3://$(STACKIT_BUCKET)/$(S3_OBJECT_PATH)'
## Clean up build artifacts
clean:
	@echo 'Cleaning up...'
	rm -rf otel-collector-release-*.tgz $(S3_CONFIG) blobs dev_releases .dev_builds