import { readFileSync } from 'node:fs';

export interface LayoutBlock {
  tag: string;
  x: number;
  y: number;
  width: number;
  height: number;
  sample: string;
}

export interface VisionBundle {
  scrapedText: string;
  screenshotPath: string | null;
  layoutBlocks: LayoutBlock[];
}

export type ChatPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string } };

export function renderLayoutMap(blocks: LayoutBlock[], viewport = '1440x900'): string {
  if (blocks.length === 0) return '';
  const rows = blocks
    .map(
      (b, i) =>
        `#${i + 1} ${b.tag}@(${Math.round(b.x)},${Math.round(b.y)}) ${Math.round(b.width)}x${Math.round(b.height)} :: ${b.sample.trim()}`
    )
    .join('\n');
  return `dom layout map, viewport ${viewport}:\n${rows}`;
}

export function buildIngestPayload(bundle: VisionBundle, modelVisionCapable: boolean): ChatPart[] {
  if (modelVisionCapable && bundle.screenshotPath) {
    const base64 = readFileSync(bundle.screenshotPath).toString('base64');
    return [
      {
        type: 'text',
        text: 'inspect the captured web generation. validate formatting, structural artifacts, or truncation.',
      },
      { type: 'image_url', image_url: { url: `data:image/png;base64,${base64}` } },
    ];
  }
  const layout = renderLayoutMap(bundle.layoutBlocks);
  const text = layout ? `${bundle.scrapedText}\n\n${layout}` : bundle.scrapedText;
  return [{ type: 'text', text }];
}
