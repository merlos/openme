BINARY   = openme
DIST     = dist
MODULE   = github.com/merlos/openme

# Infer version from the most recent git tag (strips leading 'v').
# Override on the command line: make release VERSION=1.2.3
VERSION  ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0-dev")

DEB_STAGING = $(DIST)/.deb-staging

TARGETS = \
	linux/amd64 \
	linux/arm64 \
	darwin/amd64 \
	darwin/arm64 \
	windows/amd64

.PHONY: all build test lint clean docs build-all release \
        package-deb package-deb-amd64 package-deb-arm64

all: build

## Build for the current platform
build:
	go build -o $(BINARY) ./cmd/openme

## Run all tests with race detector and coverage
test:
	go test -race -coverprofile=coverage.out ./...
	@echo ""
	@go tool cover -func=coverage.out | tail -1

## Run go vet and staticcheck
lint:
	go vet ./...
	@which staticcheck >/dev/null 2>&1 && staticcheck ./... || echo "staticcheck not installed — run: go install honnef.co/go/tools/cmd/staticcheck@latest"

## Cross-compile for all platforms
build-all: $(TARGETS)

$(TARGETS):
	$(eval GOOS   := $(word 1,$(subst /, ,$@)))
	$(eval GOARCH := $(word 2,$(subst /, ,$@)))
	$(eval EXT    := $(if $(filter windows,$(GOOS)),.exe,))
	@mkdir -p $(DIST)
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build -ldflags="-s -w" \
		-o $(DIST)/$(BINARY)-$(GOOS)-$(GOARCH)$(EXT) \
		./cmd/openme
	@echo "Built $(DIST)/$(BINARY)-$(GOOS)-$(GOARCH)$(EXT)"

## Generate API docs using pkgsite (requires: go install golang.org/x/pkgsite/cmd/pkgsite@latest)
docs:
	@which pkgsite >/dev/null 2>&1 || (echo "Install pkgsite: go install golang.org/x/pkgsite/cmd/pkgsite@latest" && exit 1)
	pkgsite -open .

## Build release archives with checksums
release: build-all
	@cd $(DIST) && sha256sum $(BINARY)-* > sha256sums.txt
	@echo "Release artifacts in $(DIST)/"
	@ls -lh $(DIST)/

## Remove build artifacts
clean:
	rm -rf $(DIST) $(BINARY) coverage.out

# ─── Packaging ────────────────────────────────────────────────────────────────

## Build .deb packages for both amd64 and arm64 (requires dpkg-dev)
package-deb: package-deb-amd64 package-deb-arm64

# Target-specific variables select the right arch for each .deb.
package-deb-amd64: _GOARCH  = amd64
package-deb-amd64: _DEBARCH = amd64
package-deb-arm64: _GOARCH  = arm64
package-deb-arm64: _DEBARCH = arm64

## Build a single .deb for the given arch (called via package-deb-amd64 / package-deb-arm64)
package-deb-amd64 package-deb-arm64:
	@echo "→ Building $(BINARY) $(VERSION) .deb for $(_DEBARCH) …"
	@mkdir -p $(DIST)
	CGO_ENABLED=0 GOOS=linux GOARCH=$(_GOARCH) \
		go build -ldflags="-s -w" \
		-o $(DIST)/$(BINARY)-linux-$(_GOARCH) \
		./cmd/openme

	@rm -rf  $(DEB_STAGING)
	@mkdir -p $(DEB_STAGING)/DEBIAN \
	           $(DEB_STAGING)/usr/bin \
	           $(DEB_STAGING)/lib/systemd/system \
	           $(DEB_STAGING)/etc/openme

	# Instantiate the control template
	sed 's/{{VERSION}}/$(VERSION)/; s/{{ARCH}}/$(_DEBARCH)/' \
		packaging/debian/control > $(DEB_STAGING)/DEBIAN/control

	install -m 0755 packaging/debian/postinst   $(DEB_STAGING)/DEBIAN/postinst
	install -m 0755 packaging/debian/prerm       $(DEB_STAGING)/DEBIAN/prerm
	install -m 0644 packaging/debian/conffiles   $(DEB_STAGING)/DEBIAN/conffiles

	install -m 0755 $(DIST)/$(BINARY)-linux-$(_GOARCH) \
	                $(DEB_STAGING)/usr/bin/$(BINARY)
	install -m 0644 packaging/systemd/openme.service \
	                $(DEB_STAGING)/lib/systemd/system/openme.service

	dpkg-deb --root-owner-group --build \
		$(DEB_STAGING) \
		$(DIST)/$(BINARY)_$(VERSION)_$(_DEBARCH).deb
	@echo "Created $(DIST)/$(BINARY)_$(VERSION)_$(_DEBARCH).deb"
