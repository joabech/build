################################################################################
# fetch-by-similarity-submission
#
# This repo keeps its own submission/niobium-client checkout (with
# submodules), separate from the top-level niobium-client git, because the
# scoring harness hardcodes that exact path and we don't want to patch it.
# The submodules are synced by the install: step in sdk.yml before -build
# runs.
################################################################################

.PHONY: fetch-by-similarity-submission-build fetch-by-similarity-submission-test fetch-by-similarity-submission-clean

# -j1: same ordering issue as niobium-client-release in niobium-client.mk.
fetch-by-similarity-submission-build:
	$(MAKE) -j1 -C $(FETCH_BY_SIMILARITY_SUBMISSION_DIR)/submission/niobium-client release
	cd $(FETCH_BY_SIMILARITY_SUBMISSION_DIR) && \
		./scripts/build_task.sh \
			./submission \
			./submission/niobium-client/vendor/lib/openfhe

fetch-by-similarity-submission-test:
	cd $(FETCH_BY_SIMILARITY_SUBMISSION_DIR) && \
		$(FETCH_BY_SIMILARITY_SUBMISSION_VENV)/bin/python3 harness/run_submission.py 0 \
			--seed 12345 --count_only

fetch-by-similarity-submission-clean:
	rm -rf $(FETCH_BY_SIMILARITY_SUBMISSION_DIR)/submission/build
