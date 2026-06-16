package version

import (
	"runtime/debug"
	"time"
)

// buildTimestamp returns a compact timestamp string derived from the
// vcs.time build-info setting embedded by `go build` when the source
// tree is inside a Git (or other VCS) repository.
//
// Format: "YYYY-MM-DD-HHMM" (e.g. "2026-06-23-1414").
// Returns an empty string when build info is unavailable (e.g. in tests
// built with `go test` without a VCS-tracked source tree).
func buildTimestamp() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return ""
	}
	for _, s := range info.Settings {
		if s.Key == "vcs.time" && s.Value != "" {
			t, err := time.Parse(time.RFC3339, s.Value)
			if err != nil {
				return ""
			}
			return t.UTC().Format("2006-01-02-1504")
		}
	}
	return ""
}
