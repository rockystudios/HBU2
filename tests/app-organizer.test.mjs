import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");

function node() {
  const classes = new Set();
  return {
    children: [], hidden: false, value: "", textContent: "", attributes: {}, dataset: {},
    style: { setProperty(name, value) { this[name] = value; } },
    classList: { toggle(name, on) { on ? classes.add(name) : classes.delete(name); }, contains(name) { return classes.has(name); } },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(type, fn) { this[type] = fn; },
    append(child) { this.children.push(child); },
    replaceChildren() { this.children = []; },
    querySelectorAll() { return this.children; },
    focus() {}
  };
}

test("app categories and persistent pins handle unavailable and player apps", () => {
  const grid = node();
  for (const [id, label, hidden] of [["chat", "Chat", false], ["paint", "Paint", false], ["owner", "Owner", true], ["ua-123", "Player app", false]]) {
    const icon = node();
    icon.dataset.app = id;
    icon.hidden = hidden;
    icon.querySelector = () => ({ textContent: label });
    grid.append(icon);
  }
  const category = node();
  category.value = "all";
  const toggle = node();
  const panel = node();
  panel.hidden = true;
  const list = node();
  const status = node();
  status.hidden = true;
  const nodes = { ".app-grid": grid, "#app-category": category, "#app-pin-toggle": toggle, "#app-pin-panel": panel, "#app-pin-list": list, "#app-organizer-status": status };
  let saved;
  const context = {
    document: { querySelector: id => nodes[id], createElement: node },
    readLocal: () => [], writeLocal: (key, value) => { saved = [key, [...value]]; return true; },
    MutationObserver: class { observe() {} }
  };
  const start = source.indexOf('    const appGrid = document.querySelector(".app-grid");');
  const end = source.indexOf("    const safeIcon =", start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), context);
  assert.equal(list.children.length, 3);
  assert.equal(list.children.some(button => button.textContent === "Owner"), false);
  toggle.click();
  assert.equal(panel.hidden, false);
  list.children.find(button => button.textContent === "Paint").click();
  assert.deepEqual(saved, ["hbu-pinned-apps", ["paint"]]);
  assert.equal(grid.children[1].style.order, "0");
  category.value = "pinned";
  category.change();
  assert.equal(grid.children[0].classList.contains("app-filtered"), true);
  assert.equal(grid.children[1].classList.contains("app-filtered"), false);
  category.value = "custom";
  category.change();
  assert.equal(grid.children[3].classList.contains("app-filtered"), false);
  assert.equal(grid.children[1].classList.contains("app-filtered"), true);
  grid.children[2].hidden = false;
  category.value = "tools";
  category.change();
  assert.equal(grid.children[2].classList.contains("app-filtered"), false);
  assert.equal(list.children.some(button => button.textContent === "Owner"), true);
});
