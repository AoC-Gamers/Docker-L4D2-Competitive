PYTHON ?= python3
QUALITY_PYTHON ?= tmp/quality-venv/bin/python
.PHONY: help test shellcheck sonar quality-setup python-coverage sonar-tooling-test sonar-issues sonar-coverage sonar-duplications sonar-hotspots
help:
	@echo 'quality-setup | python-coverage | test | shellcheck | sonar | sonar-tooling-test | sonar-issues | sonar-coverage | sonar-duplications | sonar-hotspots'
test:
	@$(QUALITY_PYTHON) -c "import coverage"
	@PATH="$(abspath $(dir $(QUALITY_PYTHON))):$$PATH" bash scripts/test-stack.sh
shellcheck:
	@bash scripts/shellcheck.sh
quality-setup:
	@$(PYTHON) -m venv tmp/quality-venv
	@$(QUALITY_PYTHON) -m pip install -r requirements-quality.txt
python-coverage:
	@$(QUALITY_PYTHON) scripts/make_sonar.py coverage-run
sonar: shellcheck
	@$(QUALITY_PYTHON) scripts/make_sonar.py analyze
sonar-tooling-test:
	@PYTHONDONTWRITEBYTECODE=1 $(QUALITY_PYTHON) -m unittest discover -s scripts/sonar_tests -v
sonar-issues sonar-coverage sonar-duplications sonar-hotspots:
	@$(PYTHON) scripts/make_sonar.py $(patsubst sonar-%,%,$@)
