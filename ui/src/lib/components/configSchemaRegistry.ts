import { getComponentConfigSchema, type GenericSectionDef } from "./componentConfigSchemas";
import { getStaticSections } from "./configSchemas";

export type ConfigUiKind = "nullclaw" | "structured" | "raw";
export type NullclawConfigGroup =
  | "general"
  | "providers"
  | "channels"
  | "behavior"
  | "reliability"
  | "memory"
  | "peripherals"
  | "advanced";

export const NULLCLAW_CONFIG_GROUP_LABELS: Record<NullclawConfigGroup, string> = {
  general: "General",
  providers: "Providers",
  channels: "Channels",
  behavior: "Behavior",
  reliability: "Reliability & Security",
  memory: "Memory",
  peripherals: "Peripherals",
  advanced: "Advanced / Raw",
};

export function getConfigUiKind(component: string): ConfigUiKind {
  if (component === "nullclaw") return "nullclaw";
  return getComponentConfigSchema(component).length > 0 ? "structured" : "raw";
}

export function supportsVisualConfig(component: string): boolean {
  return getConfigUiKind(component) !== "raw";
}

export function getVisualConfigSectionCount(component: string): number {
  if (component === "nullclaw") return getStaticSections().length;
  return getComponentConfigSchema(component).length;
}

export function getNullclawSectionGroups(): Array<{
  key: NullclawConfigGroup;
  label: string;
  sections: GenericSectionDef[];
}> {
  const grouped = new Map<NullclawConfigGroup, GenericSectionDef[]>();

  for (const section of getStaticSections()) {
    const group = (section.group as NullclawConfigGroup | undefined) ?? "advanced";
    const current = grouped.get(group) ?? [];
    current.push(section);
    grouped.set(group, current);
  }

  return (Object.keys(NULLCLAW_CONFIG_GROUP_LABELS) as NullclawConfigGroup[])
    .map((key) => ({
      key,
      label: NULLCLAW_CONFIG_GROUP_LABELS[key],
      sections: grouped.get(key) ?? [],
    }))
    .filter((group) => group.sections.length > 0);
}
