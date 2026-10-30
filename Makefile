PYTHON ?= python3
.PHONY: help test shellcheck sonar sonar-tooling-test sonar-issues sonar-coverage sonar-duplications sonar-hotspots
help:
	@echo 'test | shellcheck | sonar | sonar-tooling-test | sonar-issues | sonar-coverage | sonar-duplications | sonar-hotspots'
test:
	@bash scripts/test-stack.sh
shellcheck:
	@bash scripts/shellcheck.sh
sonar: test shellcheck
	@$(PYTHON) scripts/make_sonar.py analyze
sonar-tooling-test:
	@PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover -s scripts/sonar_tests -v
sonar-issues sonar-coverage sonar-duplications sonar-hotspots:
	@$(PYTHON) scripts/make_sonar.py $(patsubst sonar-%,%,$@)
