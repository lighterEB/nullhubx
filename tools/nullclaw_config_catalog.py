#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
NULLCLAW_ROOT = Path('/home/huspc/projects/nullclaw')

CONFIG_EXAMPLE = NULLCLAW_ROOT / 'config.example.json'
CONFIG_ZIG = NULLCLAW_ROOT / 'src' / 'config.zig'
CONFIG_TYPES = NULLCLAW_ROOT / 'src' / 'config_types.zig'
CONFIG_PARSE = NULLCLAW_ROOT / 'src' / 'config_parse.zig'
UI_SCHEMA_TS = ROOT / 'ui' / 'src' / 'lib' / 'components' / 'configSchemas.ts'

CATALOG_JSON = ROOT / 'docs' / 'nullclaw-config-catalog.json'
COVERAGE_MD = ROOT / 'docs' / 'nullclaw-ui-coverage-report.md'

SKIP_FIELDS = {
    'allocator',
    'arena',
    'config_path',
    'workspace_dir',
    'workspace_dir_override',
    'temperature',
    'max_tokens',
    'memory_backend',
    'memory_auto_save',
    'heartbeat_enabled',
    'heartbeat_interval_minutes',
    'gateway_host',
    'gateway_port',
    'workspace_only',
    'max_actions_per_hour',
    'legacy_default_provider_detected',
    'legacy_default_model_detected',
    'agent_bindings_runtime_owned',
    'token_limit_explicit',
    'state_dir',
    'config_dir',
}


@dataclass
class LeafField:
    path: str
    value_type: str
    source: str
    default: str | None = None
    enum_values: list[str] | None = None


@dataclass
class StructField:
    name: str
    field_type: str
    default: str | None


@dataclass
class CatalogEntry:
    path: str
    types: set[str] = field(default_factory=set)
    sources: set[str] = field(default_factory=set)
    defaults: set[str] = field(default_factory=set)
    enum_values: set[str] = field(default_factory=set)


def normalize_path(path: str) -> str:
    path = re.sub(r"^channels\.([^.]+)\[\*\]\.", r"channels.\1.accounts.<account>.", path)
    path = re.sub(r"^channels\.([^.]+)\[\*\]$", r"channels.\1.accounts.<account>", path)
    path = re.sub(r"\.accounts\.[^.]+", ".accounts.<account>", path)
    return path


def flatten_example(obj: Any, prefix: str = "") -> list[LeafField]:
    fields: list[LeafField] = []

    if isinstance(obj, dict):
        if not obj:
            fields.append(LeafField(prefix, 'object', 'config.example.json'))
            return fields
        for k, v in obj.items():
            p = f"{prefix}.{k}" if prefix else k
            fields.extend(flatten_example(v, p))
        return fields

    if isinstance(obj, list):
        if not obj:
            fields.append(LeafField(prefix, 'array', 'config.example.json'))
            return fields
        first = obj[0]
        if isinstance(first, dict):
            fields.extend(flatten_example(first, f"{prefix}[*]"))
        else:
            fields.append(LeafField(prefix, 'array', 'config.example.json'))
        return fields

    t = type(obj).__name__
    if t == 'NoneType':
        t = 'null'
    elif t == 'str':
        t = 'string'
    elif t == 'int':
        t = 'int'
    elif t == 'float':
        t = 'float'
    elif t == 'bool':
        t = 'bool'
    fields.append(LeafField(prefix, t, 'config.example.json'))
    return fields


def strip_line_comment(line: str) -> str:
    in_str = False
    escaped = False
    for i, ch in enumerate(line):
        if ch == '"' and not escaped:
            in_str = not in_str
        if not in_str and ch == '/' and i + 1 < len(line) and line[i + 1] == '/':
            return line[:i]
        escaped = (ch == '\\' and not escaped)
        if ch != '\\':
            escaped = False
    return line


def brace_delta(line: str) -> int:
    s = strip_line_comment(line)
    in_str = False
    escaped = False
    delta = 0
    for ch in s:
        if ch == '"' and not escaped:
            in_str = not in_str
        elif not in_str:
            if ch == '{':
                delta += 1
            elif ch == '}':
                delta -= 1
        escaped = (ch == '\\' and not escaped)
        if ch != '\\':
            escaped = False
    return delta


def find_matching_brace(src: str, open_idx: int) -> int:
    depth = 0
    in_str = False
    escaped = False
    in_line_comment = False

    i = open_idx
    while i < len(src):
        ch = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ''

        if in_line_comment:
            if ch == '\n':
                in_line_comment = False
            i += 1
            continue

        if not in_str and ch == '/' and nxt == '/':
            in_line_comment = True
            i += 2
            continue

        if ch == '"' and not escaped:
            in_str = not in_str

        if not in_str:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return i

        escaped = (ch == '\\' and not escaped)
        if ch != '\\':
            escaped = False
        i += 1

    return -1


def parse_struct_fields(body: str) -> list[StructField]:
    fields: list[StructField] = []
    depth = 0

    for raw in body.splitlines():
        line = strip_line_comment(raw).strip()
        if not line:
            depth += brace_delta(raw)
            continue

        if depth == 0 and ':' in line and line.endswith(','):
            if line.startswith('pub ') or line.startswith('fn '):
                pass
            else:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=,]+?)(?:\s*=\s*(.*))?,$", line)
                if m:
                    name = m.group(1)
                    field_type = m.group(2).strip()
                    default = m.group(3).strip() if m.group(3) else None
                    fields.append(StructField(name=name, field_type=field_type, default=default))

        depth += brace_delta(raw)

    return fields


def parse_enum_values(body: str) -> list[str]:
    vals: list[str] = []
    depth = 0

    for raw in body.splitlines():
        line = strip_line_comment(raw).strip()
        if not line:
            depth += brace_delta(raw)
            continue

        if depth == 0 and line.endswith(','):
            if line.startswith('pub ') or line.startswith('fn '):
                pass
            else:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", line)
                if m:
                    vals.append(m.group(1))

        depth += brace_delta(raw)

    return vals


def parse_config_types_definitions() -> tuple[dict[str, list[StructField]], dict[str, list[str]]]:
    src = CONFIG_TYPES.read_text(encoding='utf-8')
    structs: dict[str, list[StructField]] = {}
    enums: dict[str, list[str]] = {}

    for m in re.finditer(r"pub const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(struct|enum)\s*\{", src):
        name = m.group(1)
        kind = m.group(2)
        open_idx = m.end() - 1
        close_idx = find_matching_brace(src, open_idx)
        if close_idx == -1:
            continue
        body = src[open_idx + 1:close_idx]

        if kind == 'struct':
            structs[name] = parse_struct_fields(body)
        else:
            enums[name] = parse_enum_values(body)

    return structs, enums


def extract_top_level_sections_from_config_zig() -> dict[str, str]:
    text = CONFIG_ZIG.read_text(encoding='utf-8')
    m = re.search(r"// Nested sub-configs(?P<body>.*?)// Convenience aliases", text, re.S)
    if not m:
        return {}

    body = m.group('body')
    out: dict[str, str] = {}
    for field, typ in re.findall(r"\n\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*([A-Za-z0-9_]+)\s*=\s*\.\{\},", body):
        out[field] = typ
    return out


def is_scalar_type(t: str, enums: dict[str, list[str]]) -> bool:
    t = t.strip()
    if t in enums:
        return True
    if t.startswith('?'):
        return is_scalar_type(t[1:], enums)
    if t.startswith('*'):
        return is_scalar_type(t[1:], enums)
    if t.startswith('[]const '):
        inner = t[len('[]const '):].strip()
        # list of primitives (or string)
        if inner in enums:
            return True
        if inner.startswith('u8') or inner in {'u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'i32', 'i64', 'f32', 'f64', 'bool', 'usize', 'isize'}:
            return True
        # []const []const u8 etc considered scalar list leaf
        if inner.startswith('[]const u8') or inner.startswith('?[]const u8'):
            return True
        return False

    return t.startswith('u') or t.startswith('i') or t.startswith('f') or t in {
        'bool',
        'usize',
        'isize',
        '[]const u8',
        '?[]const u8',
    }


def normalize_scalar_type(t: str) -> str:
    s = t.replace(' ', '')
    if s in {'[]constu8', '?[]constu8'}:
        return 'string'
    if s in {'[]const[]constu8', '?[]const[]constu8'}:
        return 'array'
    if s.startswith('?'):
        s = s[1:]
    if s.startswith('*'):
        s = s[1:]
    if s == '[]constu8':
        return 'string'
    if s.startswith('[]const'):
        return 'array'
    if s in {'bool'}:
        return 'bool'
    if s.startswith('u') or s.startswith('i') or s in {'usize', 'isize'}:
        return 'int'
    if s.startswith('f'):
        return 'float'
    return 'string'


def unwrap_optional_and_ptr(t: str) -> str:
    s = t.strip()
    while s.startswith('?') or s.startswith('*'):
        s = s[1:].strip()
    return s


def array_inner_type(t: str) -> str | None:
    s = unwrap_optional_and_ptr(t)
    if s.startswith('[]const '):
        return s[len('[]const '):].strip()
    return None


def expand_struct_paths(
    struct_name: str,
    prefix: str,
    structs: dict[str, list[StructField]],
    enums: dict[str, list[str]],
    out: list[LeafField],
    visited: set[tuple[str, str]],
) -> None:
    key = (struct_name, prefix)
    if key in visited:
        return
    visited.add(key)

    for f in structs.get(struct_name, []):
        if f.name in SKIP_FIELDS:
            continue

        fpath = f"{prefix}.{f.name}" if prefix else f.name
        ftype = f.field_type.strip()

        # Scalar or enum leaf
        if is_scalar_type(ftype, enums):
            enum_vals = enums.get(unwrap_optional_and_ptr(ftype))
            out.append(LeafField(
                path=fpath,
                value_type=normalize_scalar_type(ftype),
                source='config_types.zig',
                default=f.default,
                enum_values=enum_vals,
            ))
            continue

        # Struct leaf recursion
        direct_type = unwrap_optional_and_ptr(ftype)
        if direct_type in structs:
            expand_struct_paths(direct_type, fpath, structs, enums, out, visited)
            continue

        # Array types
        inner = array_inner_type(ftype)
        if inner is not None:
            inner_unwrapped = unwrap_optional_and_ptr(inner)
            if inner_unwrapped in structs:
                item_prefix = f"{fpath}[*]"
                expand_struct_paths(inner_unwrapped, item_prefix, structs, enums, out, visited)
            else:
                out.append(LeafField(
                    path=fpath,
                    value_type='array',
                    source='config_types.zig',
                    default=f.default,
                ))
            continue

        # Fallback
        out.append(LeafField(
            path=fpath,
            value_type='unknown',
            source='config_types.zig',
            default=f.default,
        ))


def expand_channels_from_types(
    structs: dict[str, list[StructField]],
    enums: dict[str, list[str]],
) -> list[LeafField]:
    out: list[LeafField] = []
    visited: set[tuple[str, str]] = set()

    channels_fields = structs.get('ChannelsConfig', [])
    for f in channels_fields:
        if f.name == 'cli':
            out.append(LeafField(path='channels.cli', value_type='bool', source='config_types.zig', default=f.default))
            continue

        inner = array_inner_type(f.field_type)
        direct = unwrap_optional_and_ptr(f.field_type)

        # multi-account channels
        if inner is not None and unwrap_optional_and_ptr(inner) in structs:
            inner_struct = unwrap_optional_and_ptr(inner)
            acct_prefix = f"channels.{f.name}.accounts.<account>"
            expand_struct_paths(inner_struct, acct_prefix, structs, enums, out, visited)
            continue

        # single-object channel configs (webhook, nostr)
        if direct in structs:
            expand_struct_paths(direct, f"channels.{f.name}", structs, enums, out, visited)
            continue

    return out


def parse_config_parse_paths() -> set[str]:
    lines = CONFIG_PARSE.read_text(encoding='utf-8').splitlines()
    paths: set[str] = set()

    # scoped variable map: (var, path, min_depth)
    scoped: list[tuple[str, str, int]] = []
    depth = 0

    def prune(current_depth: int) -> None:
        nonlocal scoped
        scoped = [x for x in scoped if x[2] <= current_depth]

    def bind(var: str, path: str, scope_depth: int) -> None:
        scoped.append((var, path, scope_depth))

    def resolve(var: str) -> str | None:
        for v, p, _d in reversed(scoped):
            if v == var:
                return p
        return None

    for raw in lines:
        line = strip_line_comment(raw)
        prune(depth)

        # if (root.get("x")) |var| {
        m_root = re.search(r"if\s*\(\s*root\.get\(\"([^\"]+)\"\)\s*\)\s*\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|", line)
        if m_root:
            key, var = m_root.group(1), m_root.group(2)
            paths.add(key)
            bind(var, key, depth + 1)

        # if (var.object.get("x")) |child| {
        m_obj = re.search(r"if\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\.object\.get\(\"([^\"]+)\"\)\s*\)\s*\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|", line)
        if m_obj:
            parent, key, child = m_obj.group(1), m_obj.group(2), m_obj.group(3)
            p = resolve(parent)
            if p:
                full = f"{p}.{key}"
                paths.add(full)
                bind(child, full, depth + 1)

        # if (var.get("x")) |child| {
        m_get = re.search(r"if\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\.get\(\"([^\"]+)\"\)\s*\)\s*\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|", line)
        if m_get:
            parent, key, child = m_get.group(1), m_get.group(2), m_get.group(3)
            p = resolve(parent)
            if p:
                full = f"{p}.{key}"
                paths.add(full)
                bind(child, full, depth + 1)

        # const alias = var.object;
        m_alias = re.search(r"const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\.object\s*;", line)
        if m_alias:
            alias, parent = m_alias.group(1), m_alias.group(2)
            p = resolve(parent)
            if p:
                bind(alias, p, depth + 1)

        depth += brace_delta(raw)

    return paths


def derive_leaf_paths(paths: set[str]) -> set[str]:
    leafs = set(paths)
    for p in paths:
        prefix = p + '.'
        if any(q != p and q.startswith(prefix) for q in paths):
            leafs.discard(p)
    return leafs


def extract_ui_paths() -> tuple[set[str], list[str]]:
    text = UI_SCHEMA_TS.read_text(encoding='utf-8')

    static_match = re.search(r"export const staticSections:\s*SectionDef\[\]\s*=\s*\[(.*?)]\s*;", text, re.S)
    static_body = static_match.group(1) if static_match else ''
    static_paths = set(re.findall(r"\{\s*key:\s*'([^']+)'", static_body))

    channel_match = re.search(r"export const channelSchemas: Record<string, ChannelSchema> = \{(.*?)\n\};", text, re.S)
    if not channel_match:
        return static_paths, []

    body = channel_match.group(1)
    entry_iter = re.finditer(r"\n\s{2}([a-z0-9_]+):\s*\{(.*?)\n\s{2}\},?", body, re.S)

    ui_paths = set(static_paths)
    channels: list[str] = []

    for em in entry_iter:
        channel = em.group(1)
        entry = em.group(2)
        channels.append(channel)
        has_accounts = bool(re.search(r"hasAccounts:\s*true", entry))
        keys = re.findall(r"\{\s*key:\s*'([^']+)'", entry)

        if channel == 'cli':
            ui_paths.add('channels.cli')
            continue

        for key in keys:
            if has_accounts:
                ui_paths.add(f"channels.{channel}.accounts.<account>.{key}")
            else:
                ui_paths.add(f"channels.{channel}.{key}")

    return ui_paths, sorted(set(channels))


def add_entry(entries: dict[str, CatalogEntry], field: LeafField) -> None:
    p = normalize_path(field.path)
    entry = entries.setdefault(p, CatalogEntry(path=p))
    entry.types.add(field.value_type)
    entry.sources.add(field.source)
    if field.default is not None:
        entry.defaults.add(field.default)
    if field.enum_values:
        entry.enum_values.update(field.enum_values)


def main() -> None:
    config = json.loads(CONFIG_EXAMPLE.read_text(encoding='utf-8'))
    example_fields = flatten_example(config)

    structs, enums = parse_config_types_definitions()
    top_sections = extract_top_level_sections_from_config_zig()

    type_fields: list[LeafField] = []
    visited: set[tuple[str, str]] = set()

    for section, section_type in sorted(top_sections.items()):
        if section == 'channels':
            continue
        if section_type in structs:
            expand_struct_paths(section_type, section, structs, enums, type_fields, visited)

    type_fields.extend(expand_channels_from_types(structs, enums))

    parse_paths = parse_config_parse_paths()
    parse_leafs = derive_leaf_paths(parse_paths)
    parse_fields = [LeafField(path=p, value_type='unknown', source='config_parse.zig') for p in sorted(parse_leafs)]

    entries: dict[str, CatalogEntry] = {}
    for f in example_fields:
        add_entry(entries, f)
    for f in type_fields:
        add_entry(entries, f)
    for f in parse_fields:
        add_entry(entries, f)

    # Remove clearly runtime-only paths after merge.
    for k in list(entries.keys()):
        if any(part in SKIP_FIELDS for part in k.split('.')):
            del entries[k]

    # Keep only leaf paths in the merged catalog to avoid section-level duplicates.
    all_paths = list(entries.keys())
    for p in all_paths:
        prefix = p + '.'
        if any(q != p and q.startswith(prefix) for q in entries.keys()):
            entries.pop(p, None)

    ui_paths, ui_channels = extract_ui_paths()

    catalog_payload = {
        'version': 2,
        'generated_at': datetime.now(UTC).isoformat(),
        'source_priority': [
            '/home/huspc/projects/nullclaw/src/config_types.zig',
            '/home/huspc/projects/nullclaw/src/config_parse.zig',
            '/home/huspc/projects/nullclaw/src/config.zig',
            '/home/huspc/projects/nullclaw/config.example.json',
            '/home/huspc/projects/nullclaw/docs/zh/configuration.md',
        ],
        'notes': [
            'catalog v2 = config.example 扁平字段 + config_types 结构化字段 + config_parse 实际解析叶子字段。',
            'channels 的多账号路径统一规范为 channels.<type>.accounts.<account>.*。',
            '仍有少量动态/数组对象键只能通过运行时样本补全。',
        ],
        'top_level_sections_from_config_zig': sorted(top_sections.keys()),
        'ui_schema_channels': ui_channels,
        'enum_count': len(enums),
        'struct_count': len(structs),
        'leaf_fields': [
            {
                'path': e.path,
                'types': sorted(e.types),
                'sources': sorted(e.sources),
                'defaults': sorted(e.defaults),
                'enum_values': sorted(e.enum_values),
            }
            for e in sorted(entries.values(), key=lambda x: x.path)
        ],
    }

    CATALOG_JSON.write_text(json.dumps(catalog_payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    catalog_paths = {f['path'] for f in catalog_payload['leaf_fields']}
    matched = sorted(catalog_paths & ui_paths)
    missing = sorted(catalog_paths - ui_paths)

    by_top: dict[str, int] = defaultdict(int)
    by_top_missing: dict[str, int] = defaultdict(int)
    for p in catalog_paths:
        by_top[p.split('.')[0]] += 1
    for p in missing:
        by_top_missing[p.split('.')[0]] += 1

    coverage = (len(matched) / len(catalog_paths) * 100.0) if catalog_paths else 0.0

    lines: list[str] = []
    lines.append('# NullClaw 配置可视化覆盖差异报告 (v2)')
    lines.append('')
    lines.append(f'- Catalog 字段总数: **{len(catalog_paths)}**')
    lines.append(f'- UI 已覆盖字段: **{len(matched)}**')
    lines.append(f'- UI 未覆盖字段: **{len(missing)}**')
    lines.append(f'- 覆盖率: **{coverage:.2f}%**')
    lines.append('')
    lines.append('## 数据来源占比')
    lines.append('')
    source_count: dict[str, int] = defaultdict(int)
    for f in catalog_payload['leaf_fields']:
        for s in f['sources']:
            source_count[s] += 1
    for s, c in sorted(source_count.items()):
        lines.append(f'- `{s}`: {c}')

    lines.append('')
    lines.append('## 按顶层块统计（未覆盖优先）')
    lines.append('')
    lines.append('| Top-level | Total | Missing |')
    lines.append('| --- | ---: | ---: |')
    for top in sorted(by_top.keys()):
        lines.append(f"| `{top}` | {by_top[top]} | {by_top_missing.get(top, 0)} |")

    lines.append('')
    lines.append('## 未覆盖字段（前 160 项）')
    lines.append('')
    for p in missing[:160]:
        lines.append(f'- `{p}`')

    lines.append('')
    lines.append('## 说明')
    lines.append('')
    lines.append('- v2 引入了 `config_types.zig` 与 `config_parse.zig`，覆盖完整性高于 v1。')
    lines.append('- 仍建议在后续阶段增加运行时样本采集，以补齐动态 map 的键约束。')

    COVERAGE_MD.write_text('\n'.join(lines) + '\n', encoding='utf-8')

    print(f'wrote: {CATALOG_JSON}')
    print(f'wrote: {COVERAGE_MD}')
    print(f'catalog_paths={len(catalog_paths)} matched={len(matched)} coverage={coverage:.2f}%')


if __name__ == '__main__':
    main()
