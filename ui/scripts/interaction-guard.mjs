#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(scriptDir, "../src");

const VOID_TAGS = new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr",
]);

const INVALID_INSIDE_ANCHOR = new Set(["a", "button", "input", "select", "textarea"]);

/** @type {{file:string,line:number,rule:string,message:string}[]} */
const findings = [];

async function collectSvelteFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectSvelteFiles(full)));
      continue;
    }
    if (entry.isFile() && full.endsWith(".svelte")) {
      files.push(full);
    }
  }
  return files;
}

function lineNumberAt(text, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) line += 1;
  }
  return line;
}

function scanInteractiveNesting(file, text) {
  const tagRe = /<\/?([A-Za-z][\w:-]*)\b[^>]*>/g;
  /** @type {{name:string,line:number}[]} */
  const stack = [];
  let match;

  while ((match = tagRe.exec(text)) !== null) {
    const raw = match[0];
    const name = match[1].toLowerCase();
    const isClose = raw.startsWith("</");
    const line = lineNumberAt(text, match.index);

    if (!isClose) {
      const inAnchor = stack.some((item) => item.name === "a");
      const inButton = stack.some((item) => item.name === "button");

      if (inAnchor && INVALID_INSIDE_ANCHOR.has(name)) {
        findings.push({
          file,
          line,
          rule: "anchor-interactive-nesting",
          message: `<${name}> should not appear inside <a>.`,
        });
      }

      if (inButton && name === "a") {
        findings.push({
          file,
          line,
          rule: "button-anchor-nesting",
          message: "<a> should not appear inside <button>.",
        });
      }

      const selfClosing = raw.endsWith("/>") || VOID_TAGS.has(name);
      if (!selfClosing) {
        stack.push({ name, line });
      }
      continue;
    }

    for (let i = stack.length - 1; i >= 0; i -= 1) {
      if (stack[i].name === name) {
        stack.splice(i, 1);
        break;
      }
    }
  }
}

function scanOverlayDismiss(file, text) {
  const hasFullscreenCss =
    /position:\s*fixed/i.test(text) &&
    /inset:\s*0/i.test(text) &&
    /(overlay|backdrop)/i.test(text);
  if (!hasFullscreenCss) return;

  const openTagRe = /<([A-Za-z][\w:-]*)\b([^>]*)>/g;
  let match;
  while ((match = openTagRe.exec(text)) !== null) {
    const attrs = match[2] || "";
    if (!/class\s*=\s*["'][^"']*(overlay|backdrop)[^"']*["']/i.test(attrs)) continue;
    const line = lineNumberAt(text, match.index);
    if (!/\bonclick\s*=/.test(attrs)) {
      findings.push({
        file,
        line,
        rule: "fullscreen-overlay-dismiss",
        message: "Fullscreen overlay/backdrop should provide an onclick dismiss handler.",
      });
    }
  }
}

function printFindings() {
  const sorted = findings.sort((a, b) =>
    a.file === b.file ? a.line - b.line : a.file.localeCompare(b.file),
  );

  console.error("UI interaction guard failed:");
  for (const f of sorted) {
    const rel = path.relative(path.resolve(scriptDir, ".."), f.file);
    console.error(`- ${rel}:${f.line} [${f.rule}] ${f.message}`);
  }
}

async function main() {
  const files = await collectSvelteFiles(srcDir);
  for (const file of files) {
    const text = await fs.readFile(file, "utf8");
    scanInteractiveNesting(file, text);
    scanOverlayDismiss(file, text);
  }

  if (findings.length > 0) {
    printFindings();
    process.exitCode = 1;
    return;
  }

  console.log("UI interaction guard passed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
