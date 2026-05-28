/* ── Download URL builder ────────────────────────────────────────────────── */
const GH = "https://github.com/merlos/openme/releases/download";
const v  = OM_VERSIONS;

const GH_REL = "https://github.com/merlos/openme/releases";
const GH_PREV = (q) => `${GH_REL}?q=${encodeURIComponent(q)}&expanded=true`;

// Tag prefixes come from _variables.yml (written by docs/scripts/gen-variables.sh).
// Never hardcode them here — change TAG_PREFIX_* in gen-variables.sh instead.
const tp = {
  macos:   v.macos_tag_prefix,
  android: v.android_tag_prefix,
  windows: v.windows_tag_prefix,
  cli:     v.cli_tag_prefix,
};

const OM_URLS = {
  macos_dmg:     `${GH}/${tp.macos}${v.macos}/openme-macos-${v.macos}.dmg`,
  android_apk:   `${GH}/${tp.android}${v.android}/openme-${v.android}.apk`,
  win_x64:       `${GH}/${tp.windows}${v.windows}/openme-windows-${v.windows}-win-x64.zip`,
  win_arm64:     `${GH}/${tp.windows}${v.windows}/openme-windows-${v.windows}-win-arm64.zip`,
  linux_amd64:   `${GH}/${tp.cli}${v.cli}/openme-linux-amd64`,
  linux_arm64:   `${GH}/${tp.cli}${v.cli}/openme-linux-arm64`,
  linux_arm:     `${GH}/${tp.cli}${v.cli}/openme-linux-arm`,
  linux_386:     `${GH}/${tp.cli}${v.cli}/openme-linux-386`,
  linux_riscv64: `${GH}/${tp.cli}${v.cli}/openme-linux-riscv64`,
  deb_amd64:     `${GH}/${tp.cli}${v.cli}/openme_${v.cli}_amd64.deb`,
  deb_arm64:     `${GH}/${tp.cli}${v.cli}/openme_${v.cli}_arm64.deb`,
  deb_armhf:     `${GH}/${tp.cli}${v.cli}/openme_${v.cli}_armhf.deb`,
  deb_i386:      `${GH}/${tp.cli}${v.cli}/openme_${v.cli}_i386.deb`,
  deb_riscv64:   `${GH}/${tp.cli}${v.cli}/openme_${v.cli}_riscv64.deb`,
  macos_cli:     `${GH}/${tp.cli}${v.cli}/openme-darwin-arm64`,
  macos_cli_x64: `${GH}/${tp.cli}${v.cli}/openme-darwin-amd64`,
  win_cli_exe:   `${GH}/${tp.cli}${v.cli}/openme-windows-amd64.exe`,
  win_cli_arm64: `${GH}/${tp.cli}${v.cli}/openme-windows-arm64.exe`,
  releases:     GH_REL
};

/* ── OS detection ────────────────────────────────────────────────────────── */
function detectOS() {
  const ua = navigator.userAgent.toLowerCase();
  if (/android/.test(ua))             return "android";
  if (/iphone|ipad|ipod/.test(ua))    return "ios";
  if (/macintosh|mac os x/.test(ua))  return "macos";
  if (/windows/.test(ua))             return "windows";
  if (/linux/.test(ua))               return "linux";
  return "unknown";
}

/* ── Per-platform definitions ────────────────────────────────────────────── */
const PLATFORMS = {
  macos: {
    label:    "macOS",
    icon:     "bi-apple",
    headline: "openme for macOS",
    sub:      "Menu-bar app — macOS 13+",
    version:  v.macos,
    prevUrl:  GH_PREV("OpenMe macOS App"),
    buttons: [
      { label: "Download DMG", href: OM_URLS.macos_dmg, primary: true  },
      { label: "CLI (arm64)",  href: OM_URLS.macos_cli, primary: false }
    ]
  },
  ios: {
    label:    "iOS",
    icon:     "bi-phone",
    headline: "openme for iPhone",
    sub:      "Native SwiftUI app — iOS 16+",
    version:  "",
    prevUrl:  null,
    buttons: [
      { label: "App Store", href: OM_STORE.app, primary: true, external: true }
    ]
  },
  android: {
    label:    "Android",
    icon:     "bi-android2",
    headline: "openme for Android",
    sub:      "Jetpack Compose app — Android 10+",
    version:  v.android,
    prevUrl:  GH_PREV("OpenMe Android App"),
    buttons: [
      { label: "Google Play",  href: OM_STORE.play,       primary: true,  external: true },
      { label: "Download APK", href: OM_URLS.android_apk, primary: false }
    ]
  },
  windows: {
    label:    "Windows",
    icon:     "bi-windows",
    headline: "openme for Windows",
    sub:      "WPF system-tray app — Windows 10+",
    version:  v.windows,
    prevUrl:  GH_PREV("OpenMe Windows App"),
    buttons: [
      { label: "Download x64 ZIP",   href: OM_URLS.win_x64,   primary: true  },
      { label: "Download arm64 ZIP", href: OM_URLS.win_arm64, primary: false }
    ]
  },
  linux: {
    label:    "Linux",
    icon:     "bi-terminal-fill",
    headline: "openme CLI for Linux",
    sub:      "Server daemon &amp; knock client — amd64, arm64, armhf, i386, riscv64",
    version:  v.cli,
    prevUrl:  GH_PREV("OpenMe CLI"),
    buttons: [
      { label: "Download .deb (amd64)", href: OM_URLS.deb_amd64,   primary: true  },
      { label: ".deb (arm64)",          href: OM_URLS.deb_arm64,   primary: false },
      { label: ".deb (armhf)",          href: OM_URLS.deb_armhf,   primary: false },
      { label: ".deb (i386)",           href: OM_URLS.deb_i386,    primary: false },
      { label: ".deb (riscv64)",        href: OM_URLS.deb_riscv64, primary: false },
      { label: "Binary (amd64)",        href: OM_URLS.linux_amd64, primary: false },
      { label: "Binary (arm64)",        href: OM_URLS.linux_arm64, primary: false },
      { label: "Binary (armhf)",        href: OM_URLS.linux_arm,   primary: false },
      { label: "Binary (i386)",         href: OM_URLS.linux_386,   primary: false },
      { label: "Binary (riscv64)",      href: OM_URLS.linux_riscv64, primary: false }
    ]
  },
  unknown: {
    label:    "your platform",
    icon:     "bi-download",
    headline: "Download openme",
    sub:      "Platform could not be detected — see all options below.",
    version:  "",
    prevUrl:  null,
    buttons: [
      { label: "All Releases", href: OM_URLS.releases, primary: true, external: true }
    ]
  }
};

/* ── HTML helpers ────────────────────────────────────────────────────────── */
function btnHTML(b, large) {
  const cls = b.primary
    ? `btn ${large ? "btn-lg " : ""}om-btn-primary`
    : `btn ${large ? "btn-lg " : ""}om-btn-secondary`;
  const ext = b.external ? ' target="_blank" rel="noopener noreferrer"' : "";
  return `<a href="${b.href}" class="${cls}"${ext}>`
    + `<i class="bi bi-download me-2"></i>${b.label}</a>`;
}

/* ── Hero card ────────────────────────────────────────────────────────────── */
// detected=true  → shows "Detected your OS as X" note (auto-detect pages)
// detected=false → shows only "See all platforms" link (forced-platform pages)
function renderHero(os, detected = true) {
  const p   = PLATFORMS[os] || PLATFORMS.unknown;
  const ver = p.version
    ? `<span class="om-version-badge">v${p.version}</span>`
    : "";
  const note = (detected && os !== "unknown")
    ? `<p class="om-detected-note">`
      + `<i class="bi bi-geo-alt-fill me-1"></i>`
      + `Detected your operating system as <strong>${p.label}</strong>. `
      + `Not right? <a href="#all-platforms">See all platforms ↓</a></p>`
    : `<p class="om-detected-note">`
      + `<a href="#all-platforms">See all platforms ↓</a></p>`;

  document.getElementById("om-hero").innerHTML = `
<div class="om-hero-card">
  <div class="om-hero-inner">
    <div class="om-hero-icon"><i class="bi ${p.icon}"></i></div>
    <div class="om-hero-text">
      <h2 class="om-hero-title">${p.headline} ${ver}</h2>
      <p class="om-hero-sub">${p.sub}</p>
      <div class="om-btn-group">
        ${p.buttons.map(b => btnHTML(b, true)).join("\n        ")}
      </div>
      ${p.prevUrl ? `<p class="om-prev-versions"><i class="bi bi-clock-history me-1"></i><a href="${p.prevUrl}" target="_blank" rel="noopener noreferrer">Previous versions</a></p>` : ""}
    </div>
  </div>
  ${note}
</div>`;
}

/* ── All-platforms grid ──────────────────────────────────────────────────── */
function platformCard(icon, title, verLabel, links, prevUrl) {
  const linksHTML = links.map(l => {
    const ext = l.external ? ' target="_blank" rel="noopener noreferrer"' : "";
    return `<a href="${l.href}" class="om-platform-link"${ext}>`
      + `<i class="bi bi-download me-1"></i>${l.label}</a>`;
  }).join("\n      ");

  const prevHTML = prevUrl
    ? `<a href="${prevUrl}" class="om-platform-prev" target="_blank" rel="noopener noreferrer">`
      + `<i class="bi bi-clock-history me-1"></i>Previous versions</a>`
    : "";

  return `
<div class="om-platform-card">
  <div class="om-platform-header">
    <i class="bi ${icon} om-platform-icon"></i>
    <div>
      <div class="om-platform-name">${title}</div>
      <div class="om-platform-ver">${verLabel}</div>
    </div>
  </div>
  <div class="om-platform-links">
    ${linksHTML}
  </div>
  ${prevHTML}
</div>`;
}

function renderAllPlatforms() {
  const cards = [
    platformCard("bi-apple", "macOS App", `v${v.macos}`, [
      { label: "DMG (Universal)", href: OM_URLS.macos_dmg }
    ], GH_PREV("OpenMe macOS App")),
    platformCard("bi-phone", "iOS App", "App Store", [
      { label: "App Store", href: OM_STORE.app, external: true }
    ], null),
    platformCard("bi-android2", "Android App", `v${v.android}`, [
      { label: "Google Play",    href: OM_STORE.play,       external: true },
      { label: "APK (sideload)", href: OM_URLS.android_apk }
    ], GH_PREV("OpenMe Android App")),
    platformCard("bi-windows", "Windows App", `v${v.windows}`, [
      { label: "ZIP (x64)",   href: OM_URLS.win_x64   },
      { label: "ZIP (arm64)", href: OM_URLS.win_arm64 }
    ], GH_PREV("OpenMe Windows App")),
    platformCard("bi-terminal-fill", "Linux CLI", `v${v.cli}`, [
      { label: ".deb (amd64)",    href: OM_URLS.deb_amd64    },
      { label: ".deb (arm64)",    href: OM_URLS.deb_arm64    },
      { label: ".deb (armhf)",    href: OM_URLS.deb_armhf    },
      { label: ".deb (i386)",     href: OM_URLS.deb_i386     },
      { label: ".deb (riscv64)",  href: OM_URLS.deb_riscv64  },
      { label: "Binary (amd64)",  href: OM_URLS.linux_amd64  },
      { label: "Binary (arm64)",  href: OM_URLS.linux_arm64  },
      { label: "Binary (armhf)",  href: OM_URLS.linux_arm    },
      { label: "Binary (i386)",   href: OM_URLS.linux_386    },
      { label: "Binary (riscv64)",href: OM_URLS.linux_riscv64}
    ], GH_PREV("OpenMe CLI")),
    platformCard("bi-terminal", "macOS &amp; Windows CLI", `v${v.cli}`, [
      { label: "macOS (arm64)",  href: OM_URLS.macos_cli   },
      { label: "Windows (.exe)", href: OM_URLS.win_cli_exe }
    ], GH_PREV("OpenMe CLI"))
  ].join("");

  document.getElementById("om-all").innerHTML = `
<h2 id="all-platforms" class="om-section-title">All Platforms</h2>
<div class="om-platforms-grid">${cards}</div>
<p class="om-releases-footer">
  <i class="bi bi-github me-1"></i>
  All releases, changelogs and checksums on
  <a href="${OM_URLS.releases}" target="_blank" rel="noopener noreferrer">GitHub Releases</a>.
</p>`;
}
