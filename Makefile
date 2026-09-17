UV := uv
FORGE := forge

default: build

.PHONY: clean
clean:
	$(FORGE) clean
	rm -rf out/cache

.PHONY: build
build:
	$(FORGE) build

.PHONY: test
test:
	$(FORGE) test

# Kontrol proof properties (requires `kontrol` installed).
kontrol-build:
	kontrol build --verbose

.PHONY: kontrol-prove
kontrol-prove:
	kontrol prove --match-test 'ActivePoolPropertiesTest' --reinit --workers 2

.PHONY: kontrol-clean
kontrol-clean:
	kontrol clean