// One place for the facts the site states about the project.

export const site = {
  name: "ScreenPulse",
  tagline: "Ask your screen. Hear back your way.",
  description:
    "ScreenPulse is a free, open-source macOS menu bar app that explains whatever you point at on screen. Read the answer in a floating window, or let your MacBook's keyboard lights signal it.",

  /** Public repository. It becomes reachable when the repository is made public. */
  repoUrl: "https://github.com/ande060h-ui/ScreenPulse",
  licenseName: "Apache License 2.0",

  minMacOS: "macOS 13 Ventura",

  /** Set to true when the first release has been published (git tag + Release workflow). Until then
   *  the Download button is shown as "coming with the first release". */
  releaseAvailable: true,
  /** Set to true when the disk image is signed with an Apple Developer ID and notarized. Until then the
   *  site tells people how to open an app macOS has not checked. */
  signedBuilds: false,
};

export const repoLinks = {
  source: site.repoUrl,
  license: `${site.repoUrl}/blob/main/LICENSE`,
  issues: `${site.repoUrl}/issues`,
  notice: `${site.repoUrl}/blob/main/NOTICE`,
  /** A stable address: GitHub always serves the file from the newest release. */
  dmg: `${site.repoUrl}/releases/latest/download/ScreenPulse.dmg`,
  releases: `${site.repoUrl}/releases`,
};

export const nav = [
  { href: "#product", label: "Product" },
  { href: "#features", label: "Features" },
  { href: "#how", label: "How it works" },
  { href: "#get", label: "Get it" },
  { href: "#faq", label: "FAQ" },
  { href: "/setup/", label: "Get started" },
];
