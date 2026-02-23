BINARY   = openme
DIST     = dist
MODULE   = github.com/openme/openme

TARGETS = \
	linux/amd64 \
	linux/arm64 \
	darwin/amd64 \
	darwin/arm64 \
	windows/amd64

.PHONY: all build test lint clean docs build-all release

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
