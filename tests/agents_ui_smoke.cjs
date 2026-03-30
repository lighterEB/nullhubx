#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

function loadPlaywright() {
  try {
    return require("playwright");
  } catch {}

  const roots = [];
  if (process.env.NPM_CONFIG_CACHE) {
    roots.push(path.join(process.env.NPM_CONFIG_CACHE, "_npx"));
  }
  roots.push("/tmp/npm-cache/_npx");

  for (const root of roots) {
    let entries = [];
    try {
      entries = fs.readdirSync(root, { withFileTypes: true });
    } catch {
      continue;
    }

    const candidates = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => path.join(root, entry.name, "node_modules", "playwright"))
      .filter((candidate) => fs.existsSync(candidate));

    for (const candidate of candidates) {
      try {
        return require(candidate);
      } catch {}
    }
  }

  throw new Error("Cannot find playwright module");
}

async function requestJson(baseUrl, method, path, payload) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: payload ? JSON.stringify(payload) : undefined,
  });

  const text = await response.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = { _raw: text };
    }
  }

  return { status: response.status, json };
}

async function pickInstance(baseUrl) {
  const { status, json } = await requestJson(baseUrl, "GET", "/api/status");
  if (status !== 200 || !json || typeof json !== "object") {
    throw new Error("failed to load /api/status for UI smoke");
  }

  const instances = json.instances || {};
  for (const [component, names] of Object.entries(instances)) {
    if (!names || typeof names !== "object") continue;
    const firstName = Object.keys(names)[0];
    if (firstName) return { component, name: firstName };
  }
  return null;
}

async function expectVisibleAny(page, selectors, timeout = 8000) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    try {
      await locator.waitFor({ state: "visible", timeout });
      return locator;
    } catch {}
  }
  throw new Error(`none of the selectors became visible: ${selectors.join(", ")}`);
}

async function clickAny(page, selectors, timeout = 8000) {
  const locator = await expectVisibleAny(page, selectors, timeout);
  await locator.click();
  return locator;
}

async function fillLabeledInput(entry, labels, value) {
  for (const label of labels) {
    const locator = entry.locator(`label:has-text("${label}") input, label:has-text("${label}") textarea`).first();
    if (await locator.count()) {
      await locator.fill(value);
      return;
    }
  }
  throw new Error(`input label not found: ${labels.join(" / ")}`);
}

async function selectLabeledOption(entry, labels, value) {
  for (const label of labels) {
    const locator = entry.locator(`label:has-text("${label}") select`).first();
    if (await locator.count()) {
      await locator.selectOption(value);
      return;
    }
  }
  throw new Error(`select label not found: ${labels.join(" / ")}`);
}

async function readLabeledSelectValue(entry, labels) {
  for (const label of labels) {
    const locator = entry.locator(`label:has-text("${label}") select`).first();
    if (await locator.count()) {
      return locator.inputValue();
    }
  }
  throw new Error(`select label not found: ${labels.join(" / ")}`);
}

async function selectPreferredOrFirstNonEmptyOption(entry, labels, preferredValue) {
  for (const label of labels) {
    const locator = entry.locator(`label:has-text("${label}") select`).first();
    if (!(await locator.count())) continue;

    const options = await locator.locator("option").evaluateAll((nodes) =>
      nodes.map((node) => ({
        value: node.value,
        text: node.textContent || "",
      })),
    );
    const preferred = preferredValue.trim();
    const selectedValue =
      options.find((option) => option.value === preferred)?.value ||
      options.find((option) => option.value.trim().length > 0)?.value ||
      options[0]?.value;

    if (selectedValue == null) {
      throw new Error(`no options found for select label: ${labels.join(" / ")}`);
    }

    await locator.selectOption(selectedValue);
    return selectedValue;
  }
  throw new Error(`select label not found: ${labels.join(" / ")}`);
}

async function main() {
  const baseUrl = process.argv[2] || "http://127.0.0.1:19812";
  const instance = await pickInstance(baseUrl);
  if (!instance) {
    console.log("[ui-smoke] no instance found, skipping");
    return;
  }

  const profilesPath = `/api/instances/${instance.component}/${instance.name}/agents/profiles`;
  const bindingsPath = `/api/instances/${instance.component}/${instance.name}/agents/bindings`;
  const originalProfiles = await requestJson(baseUrl, "GET", profilesPath);
  const originalBindings = await requestJson(baseUrl, "GET", bindingsPath);
  assert.equal(originalProfiles.status, 200, "failed to GET original profiles");
  assert.equal(originalBindings.status, 200, "failed to GET original bindings");

  const uniqueId = `ui-smoke-${Date.now()}`;
  const bindingPeerId = `-1009999999999:thread:${Date.now() % 1000}`;

  let browser;
  try {
    const { chromium } = loadPlaywright();
    browser = await chromium.launch({ headless: true, chromiumSandbox: false });
    const page = await browser.newPage();
    await page.goto(`${baseUrl}/instances/${encodeURIComponent(instance.component)}/${encodeURIComponent(instance.name)}`, {
      waitUntil: "networkidle",
      timeout: 15000,
    });

    await clickAny(page, [
      'button:has-text("Agents")',
      'button:has-text("代理")',
    ]);

    await clickAny(page, [
      'button:has-text("Add Profile")',
      'button:has-text("添加 Profile")',
    ]);

    let profileEntry = page.locator(".entry").last();
    await fillLabeledInput(profileEntry, ["ID"], uniqueId);
    await fillLabeledInput(profileEntry, ["Provider", "服务商"], "openrouter");
    await fillLabeledInput(profileEntry, ["Model", "模型"], "openai/gpt-5-mini");
    await fillLabeledInput(profileEntry, ["System Prompt", "系统提示词"], "UI smoke profile");

    await clickAny(page, [
      'button:has-text("Save Profiles")',
      'button:has-text("保存 Profiles")',
    ]);
    await expectVisibleAny(page, [
      '.banner:has-text("Profiles saved")',
      '.banner:has-text("Profiles 已保存")',
    ]);
    await fillLabeledInput(profileEntry, ["System Prompt", "系统提示词"], "UI smoke profile updated");

    await clickAny(page, [
      'button:has-text("Bindings")',
      'button:has-text("绑定")',
    ]);
    await clickAny(page, [
      'button:has-text("Group Fallback")',
      'button:has-text("群组兜底")',
    ]);

    let bindingEntry = page.locator(".entry").last();
    await fillLabeledInput(bindingEntry, ["Agent ID"], uniqueId);
    await fillLabeledInput(bindingEntry, ["Account ID", "账户 ID"], "default");
    await fillLabeledInput(bindingEntry, ["Peer ID"], bindingPeerId);
    const bindingChannel = (await readLabeledSelectValue(bindingEntry, ["Channel", "渠道"])).trim();

    await clickAny(page, [
      'button:has-text("Save Bindings")',
      'button:has-text("保存 Bindings")',
    ]);
    await expectVisibleAny(page, [
      '.banner:has-text("Bindings saved")',
      '.banner:has-text("Bindings 已保存")',
    ]);

    await fillLabeledInput(bindingEntry, ["Account ID", "账户 ID"], "main");

    await clickAny(page, [
      'button:has-text("Save All Changes")',
      'button:has-text("保存全部改动")',
    ]);
    await expectVisibleAny(page, [
      '.banner:has-text("saved")',
      '.banner:has-text("已保存")',
    ]);

    const previewChannel = await selectPreferredOrFirstNonEmptyOption(
      page.locator(".preview-card"),
      ["Preview Channel", "预览渠道"],
      bindingChannel,
    );
    console.log(`[ui-smoke] bindingChannel=${bindingChannel} previewChannel=${previewChannel}`);
    await fillLabeledInput(page.locator(".preview-card"), ["Preview Account", "预览账户"], "main");
    await fillLabeledInput(page.locator(".preview-card"), ["Preview Peer ID", "预览 Peer ID"], bindingPeerId);
    const resolvedTarget = await expectVisibleAny(page, [
      `.preview-result-main strong:has-text("${uniqueId}")`,
    ]);
    assert.ok(await resolvedTarget.isVisible(), "route preview did not resolve the saved agent");

    console.log(`[ui-smoke] passed on ${instance.component}/${instance.name}`);
  } finally {
    if (browser) await browser.close().catch(() => {});
    await requestJson(baseUrl, "PUT", profilesPath, originalProfiles.json);
    await requestJson(baseUrl, "PUT", bindingsPath, originalBindings.json);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exit(1);
});
