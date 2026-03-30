export type ConfigFieldType =
  | "text"
  | "password"
  | "number"
  | "toggle"
  | "select"
  | "list"
  | "json"
  | "textarea";

export type ConfigEditorKind =
  | "primitive"
  | "list"
  | "json"
  | "key-value"
  | "object-list"
  | "module"
  | "raw";

export interface ConfigFieldDef {
  key: string;
  path?: string;
  aliases?: string[];
  label: string;
  type: ConfigFieldType;
  default?: unknown;
  options?: string[];
  step?: number;
  min?: number;
  max?: number;
  rows?: number;
  hint?: string;
  advanced?: boolean;
  secret?: boolean;
  nullable?: boolean;
  group?: string;
  restartRequired?: boolean;
  editorKind?: ConfigEditorKind;
  rawOnly?: boolean;
  addLabel?: string;
  emptyLabel?: string;
  itemFields?: ConfigFieldDef[];
}

export interface ConfigSectionDef {
  key: string;
  label: string;
  description?: string;
  group?: string;
  advanced?: boolean;
  fields: ConfigFieldDef[];
}

export interface ConfigChannelSchema {
  key?: string;
  label: string;
  description?: string;
  group?: string;
  hasAccounts: boolean;
  fields: ConfigFieldDef[];
}

function defaultEditorKind(type: ConfigFieldType): ConfigEditorKind {
  switch (type) {
    case "list":
      return "list";
    case "json":
      return "json";
    default:
      return "primitive";
  }
}

export function normalizeConfigField(field: ConfigFieldDef): ConfigFieldDef {
  const primaryPath = field.path ?? field.key;
  const aliases = Array.from(
    new Set(
      (field.aliases ?? []).filter((alias) => alias && alias !== primaryPath),
    ),
  );

  return {
    ...field,
    path: primaryPath,
    aliases,
    itemFields: field.itemFields?.map(normalizeConfigField),
    secret: field.secret ?? field.type === "password",
    editorKind: field.editorKind ?? defaultEditorKind(field.type),
  };
}

export function normalizeConfigSection<T extends ConfigSectionDef>(section: T): T {
  return {
    ...section,
    fields: section.fields.map(normalizeConfigField),
  };
}

export function normalizeChannelSchema<T extends ConfigChannelSchema>(schema: T, key?: string): T {
  return {
    ...schema,
    key: schema.key ?? key,
    fields: schema.fields.map(normalizeConfigField),
  };
}

export function getFieldPath(field: ConfigFieldDef): string {
  return field.path ?? field.key;
}

export function getFieldReadPaths(field: ConfigFieldDef): string[] {
  const primaryPath = getFieldPath(field);
  const readPaths = [primaryPath];

  if (field.key !== primaryPath) {
    readPaths.push(field.key);
  }

  for (const alias of field.aliases ?? []) {
    if (!readPaths.includes(alias)) {
      readPaths.push(alias);
    }
  }

  return readPaths;
}

export function getValueAtPath(obj: unknown, path: string): unknown {
  if (!path) return undefined;
  return path.split(".").reduce<unknown>((current, key) => {
    if (current === null || current === undefined || typeof current !== "object") {
      return undefined;
    }
    return (current as Record<string, unknown>)[key];
  }, obj);
}

export function getFieldValue(obj: unknown, field: ConfigFieldDef): unknown {
  for (const path of getFieldReadPaths(field)) {
    const value = getValueAtPath(obj, path);
    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

export function isComplexConfigField(field: ConfigFieldDef): boolean {
  return field.rawOnly === true
    || field.editorKind === "key-value"
    || field.editorKind === "object-list"
    || field.editorKind === "module";
}
