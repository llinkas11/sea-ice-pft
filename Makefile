# Random Forest project scaffold for the Northeast Arctic sea ice + PFT workflow.
# These targets are runnable now: they create the project structure, generate
# stage manifests, and leave clear placeholders for the full Python workflow.

SHELL := /bin/bash

.DEFAULT_GOAL := help

-include .env.make

PROJECT_ROOT ?= $(CURDIR)
DATA_ROOT ?= $(PROJECT_ROOT)
RAW_DIR := $(DATA_ROOT)/data_raw
PFT_ZIP_DIR ?= $(PROJECT_ROOT)/arctic-pfts
PFT_EXTRACT_DIR := $(RAW_DIR)/pft_daily_parquet
COPERNICUS_DIR := $(RAW_DIR)/copernicus
INSITU_DIR := $(RAW_DIR)/insitu
INTERMEDIATE_DIR := $(DATA_ROOT)/data_intermediate
MATCHUP_DIR := $(INTERMEDIATE_DIR)/matchups
FEATURE_DIR := $(INTERMEDIATE_DIR)/features
MODEL_TABLE_DIR := $(DATA_ROOT)/data_model
MODEL_DIR := $(DATA_ROOT)/models
FIGURE_DIR := $(DATA_ROOT)/figures
REPORT_DIR := $(DATA_ROOT)/reports
NOTEBOOK_DIR := $(PROJECT_ROOT)/notebooks
SCRIPT_DIR := $(PROJECT_ROOT)/scripts
LOG_DIR := $(DATA_ROOT)/logs
CODEX_NOTES_DIR := $(PROJECT_ROOT)/codex_notes
CONFIG_DIR := $(DATA_ROOT)/config

PYTHON ?= python3
EXTRACT_YEARS ?=
RUN_TS := $(shell date +%Y%m%d_%H%M%S)
PREP_LOG ?= $(LOG_DIR)/prep_$(RUN_TS).log

.PHONY: help outline init inventory extract-pfts ingest-copernicus prep-core prep-expanded \
	train-core-classifier train-core-regressor train-expanded-classifier \
	train-expanded-regressor evaluate-core evaluate-expanded validate-insitu \
	figures report scaffold hpc-check hpc-prep-full clean

help:
	@echo "Random forest project scaffold"
	@echo ""
	@echo "Recommended order:"
	@echo "  1. make init"
	@echo "  2. make inventory"
	@echo "  3. make extract-pfts"
	@echo "  4. make ingest-copernicus"
	@echo "  5. make prep-core"
	@echo "  6. make train-core-classifier"
	@echo "  7. make train-core-regressor"
	@echo "  8. make evaluate-core"
	@echo "  9. make prep-expanded"
	@echo " 10. make train-expanded-classifier"
	@echo " 11. make train-expanded-regressor"
	@echo " 12. make evaluate-expanded"
	@echo " 13. make validate-insitu"
	@echo " 14. make figures"
	@echo " 15. make report"
	@echo ""
	@echo "Scaffold notes:"
	@echo "  - Targets run with $(PYTHON)"
	@echo "  - PFT extraction is real; model fitting remains scaffolded"
	@echo "  - Train/test is documented as time-blocked, not random row split"
	@echo "  - Optional: make extract-pfts EXTRACT_YEARS=2003,2004"
	@echo "  - Optional HPC override file: .env.make"

outline:
	@echo "Project root: $(PROJECT_ROOT)"
	@echo "Data root: $(DATA_ROOT)"
	@echo "Raw PFT zip directory: $(PFT_ZIP_DIR)"
	@echo "Primary extracted PFT directory: $(PFT_EXTRACT_DIR)"
	@echo "Core workflow: response extraction -> matchup table -> RF train -> evaluation"
	@echo "Secondary workflow: core workflow + BGC predictors -> comparison of importance/performance"

init:
	$(PYTHON) $(SCRIPT_DIR)/init_project.py \
		--project-root $(PROJECT_ROOT)

inventory:
	$(PYTHON) $(SCRIPT_DIR)/inventory_data.py \
		--pft-zip-dir $(PFT_ZIP_DIR) \
		--copernicus-dir $(COPERNICUS_DIR) \
		--insitu-dir $(INSITU_DIR) \
		--output $(REPORT_DIR)/dataset_inventory.json

extract-pfts:
	$(PYTHON) $(SCRIPT_DIR)/extract_pft_archives.py \
		--input $(PFT_ZIP_DIR) \
		--output $(PFT_EXTRACT_DIR) \
		--manifest $(REPORT_DIR)/pft_extract_manifest.json \
		$(if $(EXTRACT_YEARS),--years $(EXTRACT_YEARS),)

ingest-copernicus:
	$(PYTHON) $(SCRIPT_DIR)/prepare_predictor_manifests.py \
		--copernicus-dir $(COPERNICUS_DIR) \
		--output $(REPORT_DIR)/copernicus_manifest.json

prep-core:
	$(PYTHON) $(SCRIPT_DIR)/build_pft_response_summary.py \
		--pft-dir $(PFT_EXTRACT_DIR) \
		--output $(MODEL_TABLE_DIR)/core_response_daily_summary.parquet \
		--report $(REPORT_DIR)/core_response_daily_summary.json
	$(PYTHON) $(SCRIPT_DIR)/build_model_manifest.py \
		--model-family core \
		--pft-dir $(PFT_EXTRACT_DIR) \
		--feature-dir $(FEATURE_DIR) \
		--model-table-dir $(MODEL_TABLE_DIR) \
		--matchup-dir $(MATCHUP_DIR) \
		--config-dir $(CONFIG_DIR) \
		--report-dir $(REPORT_DIR)

prep-expanded:
	$(PYTHON) $(SCRIPT_DIR)/build_pft_response_summary.py \
		--pft-dir $(PFT_EXTRACT_DIR) \
		--output $(MODEL_TABLE_DIR)/expanded_response_daily_summary.parquet \
		--report $(REPORT_DIR)/expanded_response_daily_summary.json
	$(PYTHON) $(SCRIPT_DIR)/build_model_manifest.py \
		--model-family expanded \
		--pft-dir $(PFT_EXTRACT_DIR) \
		--feature-dir $(FEATURE_DIR) \
		--model-table-dir $(MODEL_TABLE_DIR) \
		--matchup-dir $(MATCHUP_DIR) \
		--config-dir $(CONFIG_DIR) \
		--report-dir $(REPORT_DIR)

train-core-classifier:
	$(PYTHON) $(SCRIPT_DIR)/train_placeholder_model.py \
		--model-family core \
		--task classifier \
		--target pixel_class \
		--model-dir $(MODEL_DIR) \
		--report-dir $(REPORT_DIR)

train-core-regressor:
	$(PYTHON) $(SCRIPT_DIR)/train_placeholder_model.py \
		--model-family core \
		--task regressor \
		--target chlorophyll_guesses \
		--model-dir $(MODEL_DIR) \
		--report-dir $(REPORT_DIR)

train-expanded-classifier:
	$(PYTHON) $(SCRIPT_DIR)/train_placeholder_model.py \
		--model-family expanded \
		--task classifier \
		--target pixel_class \
		--model-dir $(MODEL_DIR) \
		--report-dir $(REPORT_DIR)

train-expanded-regressor:
	$(PYTHON) $(SCRIPT_DIR)/train_placeholder_model.py \
		--model-family expanded \
		--task regressor \
		--target chlorophyll_guesses \
		--model-dir $(MODEL_DIR) \
		--report-dir $(REPORT_DIR)

evaluate-core:
	$(PYTHON) $(SCRIPT_DIR)/evaluate_placeholder_model.py \
		--model-family core \
		--report-dir $(REPORT_DIR) \
		--figure-dir $(FIGURE_DIR)

evaluate-expanded:
	$(PYTHON) $(SCRIPT_DIR)/evaluate_placeholder_model.py \
		--model-family expanded \
		--report-dir $(REPORT_DIR) \
		--figure-dir $(FIGURE_DIR)

validate-insitu:
	$(PYTHON) $(SCRIPT_DIR)/validate_with_insitu.py \
		--insitu-dir $(INSITU_DIR) \
		--report-dir $(REPORT_DIR)

figures:
	$(PYTHON) $(SCRIPT_DIR)/make_figure_placeholders.py \
		--figure-dir $(FIGURE_DIR) \
		--report-dir $(REPORT_DIR)

report:
	$(PYTHON) $(SCRIPT_DIR)/build_project_summary.py \
		--project-root $(PROJECT_ROOT) \
		--report-dir $(REPORT_DIR)

hpc-check:
	@echo "PROJECT_ROOT=$(PROJECT_ROOT)"
	@echo "DATA_ROOT=$(DATA_ROOT)"
	@echo "PFT_ZIP_DIR=$(PFT_ZIP_DIR)"
	@echo "PYTHON=$(PYTHON)"
	@echo "PREP_LOG=$(PREP_LOG)"

hpc-prep-full:
	@mkdir -p $(LOG_DIR)
	@echo "Writing prep log to $(PREP_LOG)"
	@$(MAKE) init | tee $(PREP_LOG)
	@$(MAKE) inventory | tee -a $(PREP_LOG)
	@$(MAKE) extract-pfts EXTRACT_YEARS="$(EXTRACT_YEARS)" | tee -a $(PREP_LOG)
	@$(MAKE) ingest-copernicus | tee -a $(PREP_LOG)
	@$(MAKE) prep-core | tee -a $(PREP_LOG)
	@echo "HPC prep workflow complete." | tee -a $(PREP_LOG)

scaffold: init inventory extract-pfts ingest-copernicus prep-core prep-expanded \
	train-core-classifier train-core-regressor train-expanded-classifier \
	train-expanded-regressor evaluate-core evaluate-expanded validate-insitu figures report
	@echo "Scaffold run complete."

clean:
	@echo "This scaffold does not delete anything automatically."
	@echo "Add narrow cleanup rules later once generated file names are finalized."
