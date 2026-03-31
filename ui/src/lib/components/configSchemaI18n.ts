import { i18n } from "$lib/i18n/index.svelte";
import type {
  ConfigChannelSchema,
  ConfigFieldDef,
  ConfigSectionDef,
} from "./configSchemaContract";

function lookupPath(path: string): unknown {
  let current: unknown = i18n.dict;

  for (const key of path.split(".")) {
    if (current === null || current === undefined || typeof current !== "object") {
      return undefined;
    }
    current = (current as Record<string, unknown>)[key];
  }

  return current;
}

function lookupText(path: string): string | undefined {
  const value = lookupPath(path);
  return typeof value === "string" ? value : undefined;
}

function lookupLiteral(fallback: string | undefined): string | undefined {
  if (!fallback) return undefined;
  const literals = lookupPath("configSchema.literals");
  if (literals === null || literals === undefined || typeof literals !== "object") {
    return undefined;
  }
  const value = (literals as Record<string, unknown>)[fallback];
  return typeof value === "string" ? value : undefined;
}

function resolveText(fallback: string | undefined, candidates: string[]): string | undefined {
  for (const candidate of candidates) {
    const translated = lookupText(candidate);
    if (translated) return translated;
  }

  return lookupLiteral(fallback) ?? fallback;
}

function normalizeKeyPart(value: string): string {
  return value
    .replace(/\[\*\]/g, "_item")
    .replace(/[^A-Za-z0-9_-]/g, "_");
}

function normalizePath(value: string): string {
  return value
    .split(".")
    .map((part) => normalizeKeyPart(part))
    .join(".");
}

function localizeField(field: ConfigFieldDef, basePaths: string[]): ConfigFieldDef {
  const fieldPath = normalizePath(field.path ?? field.key);
  const fieldBases = basePaths.map((basePath) => `${basePath}.fields.${fieldPath}`);
  const optionLabels = field.options
    ? Object.fromEntries(
        field.options.map((option) => [
          option,
          resolveText(option, [
            ...fieldBases.map((basePath) => `${basePath}.options.${normalizeKeyPart(option)}`),
            `configSchema.options.${normalizeKeyPart(option)}`,
          ]) ?? option,
        ]),
      )
    : undefined;

  return {
    ...field,
    label: resolveText(field.label, [
      ...fieldBases.map((basePath) => `${basePath}.label`),
      `configSchema.fields.${fieldPath}.label`,
    ]) ?? field.label,
    hint: resolveText(field.hint, [
      ...fieldBases.map((basePath) => `${basePath}.hint`),
      `configSchema.fields.${fieldPath}.hint`,
    ]),
    addLabel: resolveText(field.addLabel, [
      ...fieldBases.map((basePath) => `${basePath}.addLabel`),
      `configSchema.fields.${fieldPath}.addLabel`,
    ]),
    emptyLabel: resolveText(field.emptyLabel, [
      ...fieldBases.map((basePath) => `${basePath}.emptyLabel`),
      `configSchema.fields.${fieldPath}.emptyLabel`,
    ]),
    optionLabels,
    itemFields: field.itemFields?.map((itemField) => localizeField(itemField, fieldBases)),
  };
}

function localizeSection(section: ConfigSectionDef, basePaths: string[]): ConfigSectionDef {
  const sectionBases = basePaths.map((basePath) => `${basePath}.sections.${normalizeKeyPart(section.key)}`);

  return {
    ...section,
    label: resolveText(section.label, [
      ...sectionBases.map((basePath) => `${basePath}.label`),
      `configSchema.sections.${normalizeKeyPart(section.key)}.label`,
    ]) ?? section.label,
    description: resolveText(section.description, [
      ...sectionBases.map((basePath) => `${basePath}.description`),
      `configSchema.sections.${normalizeKeyPart(section.key)}.description`,
    ]),
    fields: section.fields.map((field) => localizeField(field, sectionBases)),
  };
}

export function localizeNullclawSections(sections: ConfigSectionDef[]): ConfigSectionDef[] {
  return sections.map((section) => localizeSection(section, ["configSchema.nullclaw"]));
}

export function localizeMemorySections(sections: ConfigSectionDef[]): ConfigSectionDef[] {
  return sections.map((section) => localizeSection(section, ["configSchema.nullclaw.memory", "configSchema.nullclaw"]));
}

export function localizeComponentSections(
  component: string,
  sections: ConfigSectionDef[],
): ConfigSectionDef[] {
  return sections.map((section) =>
    localizeSection(section, [
      `configSchema.components.${normalizeKeyPart(component)}`,
      "configSchema.components.shared",
    ]),
  );
}

function localizeChannelSchema(channel: string, schema: ConfigChannelSchema): ConfigChannelSchema {
  const basePath = `configSchema.channels.${normalizeKeyPart(channel)}`;

  return {
    ...schema,
    label: resolveText(schema.label, [`${basePath}.label`]) ?? schema.label,
    description: resolveText(schema.description, [`${basePath}.description`]),
    fields: schema.fields.map((field) => localizeField(field, [basePath])),
  };
}

export function localizeChannelSchemas<T extends Record<string, ConfigChannelSchema>>(schemas: T): T {
  return Object.fromEntries(
    Object.entries(schemas).map(([channel, schema]) => [channel, localizeChannelSchema(channel, schema)]),
  ) as T;
}
