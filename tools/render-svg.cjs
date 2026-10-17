const fs = require('node:fs');
const { Resvg } = require('@resvg/resvg-js');
const [source, destination, size = '1024'] = process.argv.slice(2);
if (!source || !destination || !/^\d+$/.test(size)) {
  throw new Error('Usage: node tools/render-svg.cjs source.svg destination.png [size]');
}
const renderer = new Resvg(fs.readFileSync(source), {
  fitTo: { mode: 'width', value: Number(size) },
});
fs.writeFileSync(destination, renderer.render().asPng());
