import { readFileSync } from 'node:fs';
export function renderLayoutMap(blocks, viewport = '1440x900') {
    if (blocks.length === 0)
        return '';
    const rows = blocks
        .map((b, i) => `#${i + 1} ${b.tag}@(${Math.round(b.x)},${Math.round(b.y)}) ${Math.round(b.width)}x${Math.round(b.height)} :: ${b.sample.trim()}`)
        .join('\n');
    return `dom layout map, viewport ${viewport}:\n${rows}`;
}
export function buildIngestPayload(bundle, modelVisionCapable) {
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
