import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLayoutMap, buildIngestPayload, type LayoutBlock, type VisionBundle } from '../src/vision_routing.js';

test('vision_routing: renderLayoutMap formats layout blocks accurately', () => {
  const blocks: LayoutBlock[] = [
    { tag: 'HEADER', x: 10, y: 20, width: 800, height: 60, sample: 'Dashboard Title' },
    { tag: 'BUTTON', x: 720, y: 30, width: 80, height: 40, sample: 'Submit' },
  ];

  const rendered = renderLayoutMap(blocks, '1920x1080');
  assert.ok(rendered.includes('dom layout map, viewport 1920x1080:'));
  assert.ok(rendered.includes('#1 HEADER@(10,20) 800x60 :: Dashboard Title'));
  assert.ok(rendered.includes('#2 BUTTON@(720,30) 80x40 :: Submit'));
});

test('vision_routing: renderLayoutMap returns empty string for empty blocks', () => {
  assert.equal(renderLayoutMap([]), '');
});

test('vision_routing: buildIngestPayload for non-vision models appends DOM layout map', () => {
  const bundle: VisionBundle = {
    scrapedText: 'Page content description',
    screenshotPath: null,
    layoutBlocks: [
      { tag: 'DIV', x: 0, y: 0, width: 500, height: 300, sample: 'Card block' },
    ],
  };

  const payload = buildIngestPayload(bundle, false);
  assert.equal(payload.length, 1);
  assert.equal(payload[0].type, 'text');
  if (payload[0].type === 'text') {
    assert.ok(payload[0].text.includes('Page content description'));
    assert.ok(payload[0].text.includes('dom layout map'));
    assert.ok(payload[0].text.includes('#1 DIV@(0,0) 500x300 :: Card block'));
  }
});
