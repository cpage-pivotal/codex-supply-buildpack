SHELL := /usr/bin/env bash

.PHONY: test lint dependencies freshness test-shell sbom sbom-validate package clean

test: lint dependencies test-shell

lint:
	bash -n bin/* lib/*.sh scripts/*.sh tests/*.sh
	shellcheck -x bin/* lib/*.sh scripts/*.sh tests/*.sh

dependencies:
	scripts/check-dependencies.sh

freshness:
	scripts/check-upstream-releases.sh

test-shell:
	tests/run.sh

sbom:
	scripts/generate-sbom.sh

sbom-validate: sbom
	scripts/check-sbom.sh

package: dependencies sbom-validate
	scripts/package.sh

clean:
	rm -rf build
