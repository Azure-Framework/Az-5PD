window.NCIC_CONFIG = {
  // Window title
  title: "NCIC MDT - Police Terminal",
  // Organization / branding
  org: {
    shortName: "LSPD",                       // shown inside the badge if no logoUrl
    longName: "NCIC — Mobile Data Terminal", // main header title
    subtitle: "In-car terminal · Tactical access",
    // Optional logo image. If provided, it replaces the badge initials.
    // Use a path relative to this HTML file or a data URL.
    logoUrl: "" // e.g. "images/lspd_badge.png"
  },
  // Theme defaults (can still be changed in the Settings modal)
  theme: {
    primary: "#1a5fb4",
    primaryDark: "#154380",
    accent: "#26a269",
    accentDark: "#1e824c",
    danger: "#c01c28",
    warning: "#e5a50a",
    text: "#ffffff",
    textMuted: "#9f9f9f",
    bg: "#0b1012",
    panel: "#161a1d",
    border: "#2a2e32",
    success: "#2ec27e"
  },
  // Per-user defaults (can be changed in the Settings modal)
  defaults: {
    unit: "1-L-12",
    officer: "#3467"
  }
};