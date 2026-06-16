package version

// Version is set at build time via:
//
//	go build -ldflags "-X github.com/merlos/openme/cli/pkg/version.Version=1.2.3"
//
// When ldflags are not provided the default below is used, with the build
// timestamp appended automatically by init().
var Version = "0.0.0-dev"

// BuildDate is optionally injected at build time via -ldflags:
//
//	-X github.com/merlos/openme/cli/pkg/version.BuildDate=2026-06-23-1414
//
// When empty, init() sets it to the time the binary was compiled using the
// embed build-info timestamp.
var BuildDate = ""

func init() {
	if BuildDate == "" {
		BuildDate = buildTimestamp() // resolved at compile time via go:generate / debug.ReadBuildInfo
	}
	if Version == "0.0.0-dev" && BuildDate != "" {
		Version = "0.0.0-dev-" + BuildDate
	}
}
