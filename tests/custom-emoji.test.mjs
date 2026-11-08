import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../index.html", import.meta.url), "utf8");
const names = ["shush", "okwink", "bluegrin", "surprised", "crying", "sobbing", "laughing", "pleading"];
const pngNames = new Set(["shush", "okwink", "bluegrin", "surprised", "crying"]);

function node() {
  return {
    children: [], hidden: false, attributes: {},
    append(...children) { this.children.push(...children); },
    addEventListener(type, handler) { this[type] = handler; },
    setAttribute(name, value) { this.attributes[name] = value; }
  };
}

test("custom emoji are selectable and render in messages", async () => {
  const popup = node();
  const button = node();
  const messageText = {
    selectionStart: 2, selectionEnd: 4,
    setRangeText(...args) { this.inserted = args; },
    focus() { this.focused = true; }
  };
  const document = {
    createElement: node,
    querySelector(selector) { return selector === "#emoji-popup" ? popup : button; },
    addEventListener() {}
  };
  const context = { document, messageText, encodeURIComponent };
  const catalog = source.slice(source.indexOf("    const EMOJI_EYES ="), source.indexOf("    const APP_LOGOS ="));
  const picker = source.slice(source.indexOf("    function emojiImg("), source.indexOf("    function appendWithMentions("));
  assert.ok(catalog && picker);
  vm.runInNewContext(catalog + picker, context);
  assert.equal(popup.children.some(child => child.title === ":thumbsup:"), false);
  const removedEmoji = node();
  context.appendWithEmojis(removedEmoji, ":thumbsup:");
  assert.equal(removedEmoji.children.join(""), ":thumbsup:");

  for (const name of names) {
    const choice = popup.children.find(child => child.title === `:${name}:`);
    assert.ok(choice, `picker contains ${name}`);
    if (pngNames.has(name)) {
      assert.equal(choice.children[0].src, `assets/emoji/${name}.png`);
    } else {
      assert.match(choice.children[0].src, /^data:image\/svg\+xml/);
    }
    popup.hidden = false;
    choice.click();
    assert.deepEqual(messageText.inserted, [`:${name}: `, 2, 4, "end"]);
    assert.equal(messageText.focused, true);
    assert.equal(popup.hidden, true);
    assert.equal(button.attributes["aria-expanded"], "false");

    const rendered = node();
    context.appendWithEmojis(rendered, `Hi :${name}: :unknown:`);
    assert.equal(rendered.children[0], "Hi ");
    assert.equal(rendered.children[1].alt, `:${name}:`);
    assert.equal(rendered.children[1].src, choice.children[0].src);
    assert.equal(rendered.children[2], " :unknown:");

    if (pngNames.has(name)) {
      const png = await readFile(new URL(`../assets/emoji/${name}.png`, import.meta.url));
      assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
      assert.equal(png.readUInt32BE(16), 128);
      assert.equal(png.readUInt32BE(20), 128);
      assert.equal(png[25], 6);
    }
  }
});
