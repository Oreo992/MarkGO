// Reading modes ported from ReadingMode.swift. These are content shapes, not
// color skins: each changes width, spacing, surface and typographic tone.

export type ReadingModeId = "clear" | "paper" | "report" | "lesson" | "cards";

export interface ReadingMode {
  id: ReadingModeId;
  title: string;
  subtitle: string;
  /** Inline SVG icon path data (Lucide-style, 24x24 viewBox). */
  icon: string;
  /** Accent hex used by the mode chip + reader accent. */
  accent: string;
  shortcut: string;
}

export const READING_MODES: ReadingMode[] = [
  {
    id: "clear",
    title: "清读",
    subtitle: "打开就读",
    icon: "M4 6h16M4 12h12M4 18h16",
    accent: "#386b74",
    shortcut: "1",
  },
  {
    id: "paper",
    title: "纸页",
    subtitle: "长文纸感",
    icon: "M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM14 2v6h6",
    accent: "#8a573f",
    shortcut: "2",
  },
  {
    id: "lesson",
    title: "讲义",
    subtitle: "分节学习",
    icon: "M4 4h14a2 2 0 0 1 2 2v14H6a2 2 0 0 1-2-2zM4 4v14",
    accent: "#d09c3c",
    shortcut: "3",
  },
  {
    id: "report",
    title: "报告",
    subtitle: "正式交付",
    icon: "M6 2h9l5 5v15H6zM9 13h6M9 17h6M9 9h3",
    accent: "#574a8c",
    shortcut: "4",
  },
  {
    id: "cards",
    title: "卡片",
    subtitle: "扫读分享",
    icon: "M3 5h18v6H3zM3 13h18v6H3z",
    accent: "#944f2e",
    shortcut: "5",
  },
];

export const DEFAULT_MODE: ReadingModeId = "clear";

export function modeById(id: ReadingModeId): ReadingMode {
  return READING_MODES.find((m) => m.id === id) ?? READING_MODES[0];
}
