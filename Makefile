.PHONY: install test logs clean

VENV := .venv

# Default shard configuration
SHARD ?= 1
SPLITS ?= 1

install:
	uv venv $(VENV)
	uv pip install -r requirements-dev.txt
	@echo "Installation complete. Activate with: source $(VENV)/bin/activate"

test:
	./run-samples.sh SHARD=$(SHARD) SPLITS=$(SPLITS)

logs:
	docker logs localstack 2>&1 | tail -100

clean:
	rm -rf $(VENV)
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".aws-sam" -exec rm -rf {} + 2>/dev/null || true
