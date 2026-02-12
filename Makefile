.PHONY: test test-unit test-integration lint

test: test-unit test-integration

test-unit:
	./test/run_tests.sh unit

test-integration:
	./test/run_tests.sh integration

lint:
	shellcheck --severity=warning plugins/tandem/scripts/*.sh plugins/tandem/lib/tandem.sh
