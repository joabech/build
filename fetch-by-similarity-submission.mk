################################################################################
# fetch-by-similarity-submission
#
# This repo's own submission/niobium-client is a *separate* checkout from
# the top-level niobium-client git (not shared) and, unlike that one, keeps
# its submodules: the harness (harness/run_submission.py, harness/utils.py)
# and submission/CMakeLists.txt hardcode the path
# "submission/niobium-client" rather than accepting an override, and it's
# the scoring harness, so it's best left unpatched. Those submodules are
# synced by the fetch-by-similarity-submission-submodules install: step in
# sdk.yml, so they're already in place by the time -build runs.
################################################################################

.PHONY: fetch-by-similarity-submission-build fetch-by-similarity-submission-test fetch-by-similarity-submission-clean

# -j1: see niobium-client.mk's niobium-client-build for why this recursive
# make needs to stay serial regardless of the outer -j.
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
