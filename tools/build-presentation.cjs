const fs = require('node:fs');
const path = require('node:path');
const { Resvg } = require('@resvg/resvg-js');
const root = path.join(__dirname, '..');
const assets = path.join(root, 'assets');
const fontFiles = ['segoeui.ttf', 'segoeuib.ttf', 'malgun.ttf', 'malgunbd.ttf']
  .map(name => path.join(process.env.WINDIR || 'C:/Windows', 'Fonts', name)).filter(fs.existsSync);

function logo(color, prefix, x, y, size) {
  const svg = fs.readFileSync(path.join(assets, `${color}.svg`), 'utf8');
  const viewBox = svg.match(/viewBox="([^"]+)"/)[1];
  const content = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')
    .replace(/id="([^"]+)"/g, (_, id) => `id="${prefix}-${id}"`)
    .replace(/url\(#([^)]+)\)/g, (_, id) => `url(#${prefix}-${id})`);
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}">${content}</svg>`;
}

function save(name, svg, width) {
  fs.writeFileSync(path.join(assets, `${name}.svg`), svg);
  const image = new Resvg(svg, { fitTo: { mode: 'width', value: width },
    font: { fontFiles, loadSystemFonts: true, defaultFontFamily: 'Segoe UI' } });
  fs.writeFileSync(path.join(assets, `${name}.png`), image.render().asPng());
}

save('cover', `<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="580" viewBox="0 0 1440 580">
<defs>
 <linearGradient id="background" x2="1" y2="1"><stop stop-color="#081c31"/><stop offset=".58" stop-color="#103954"/><stop offset="1" stop-color="#081723"/></linearGradient>
 <radialGradient id="glow"><stop stop-color="#3b96b7" stop-opacity=".26"/><stop offset="1" stop-color="#3b96b7" stop-opacity="0"/></radialGradient>
 <linearGradient id="darkCard" x2="0" y2="1"><stop stop-color="#17232d"/><stop offset="1" stop-color="#090f15"/></linearGradient>
 <linearGradient id="lightCard" x2="0" y2="1"><stop stop-color="#ffffff"/><stop offset="1" stop-color="#e7edf2"/></linearGradient>
</defs>
<rect width="1440" height="580" rx="28" fill="url(#background)"/>
<ellipse cx="1145" cy="265" rx="550" ry="385" fill="url(#glow)"/>
<g fill="none" stroke="#75b6d1" stroke-opacity=".16">
 <ellipse cx="1160" cy="278" rx="470" ry="225" transform="rotate(-20 1160 278)"/>
 <ellipse cx="1160" cy="278" rx="535" ry="282" transform="rotate(-20 1160 278)"/>
 <ellipse cx="1160" cy="278" rx="605" ry="345" transform="rotate(-20 1160 278)"/>
</g>
<g font-family="Segoe UI, sans-serif">
 <rect x="66" y="54" width="184" height="40" rx="20" fill="#173d54" stroke="#497991"/>
 <text x="158" y="81" text-anchor="middle" fill="#cceaf5" font-size="20" font-weight="600" letter-spacing="1.5">WINDOWS x64</text>
 <text x="62" y="220" fill="#ffffff" font-size="101" font-weight="700" letter-spacing="-4">Aside</text>
 <text x="62" y="329" fill="#ffffff" font-size="101" font-weight="700" letter-spacing="-4">Clean Logo</text>
 <text x="69" y="390" fill="#c1d7e6" font-size="30">A cleaner icon. One click away.</text>
 <path d="M70 452H132" stroke="#77d9ee" stroke-width="4" stroke-linecap="round"/>
 <text x="69" y="506" fill="#a8c6d6" font-size="21" font-weight="600" letter-spacing="2.8">APPLY / RESTORE</text>
 <rect x="785" y="133" width="256" height="290" rx="34" fill="#030b13" opacity=".3"/>
 <rect x="784" y="127" width="256" height="290" rx="34" fill="url(#darkCard)" stroke="#4a6677"/>
 <rect x="1074" y="133" width="256" height="290" rx="34" fill="#030b13" opacity=".3"/>
 <rect x="1073" y="127" width="256" height="290" rx="34" fill="url(#lightCard)" stroke="#ecf4f9"/>
 ${logo('white', 'cover-dark', 822, 160, 180)}
 ${logo('black', 'cover-light', 1111, 160, 180)}
 <text x="912" y="385" text-anchor="middle" fill="#d6e2eb" font-size="22" font-weight="600">Dark appearance</text>
 <text x="1201" y="385" text-anchor="middle" fill="#35434d" font-size="22" font-weight="600">Light appearance</text>
 <text x="1058" y="480" text-anchor="middle" fill="#b6d7e5" font-size="23">Clean edges. Original character.</text>
</g></svg>`, 1440);

function button(name, label, fill, border, icon) {
  save(name, `<svg xmlns="http://www.w3.org/2000/svg" width="270" height="64" viewBox="0 0 270 64">
  <rect x="1" y="1" width="268" height="62" rx="12" fill="${fill}" stroke="${border}" stroke-width="2"/>
  <g fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">${icon}</g>
  <text x="153" y="41" text-anchor="middle" font-family="Malgun Gothic, Segoe UI, sans-serif" font-size="23" font-weight="700" fill="white">${label}</text></svg>`, 540);
}
button('download-apply', '로고 변경 다운로드', '#1768bd', '#3285d8', '<path d="M30 22v19m-7-7 7 7 7-7M20 45h20"/>');
button('download-restore', '원래 로고로 복원', '#233747', '#486479', '<path d="M23 27a12 12 0 1 1-1 13m1-13v-7m0 7h7"/>');
button('contentrium-home', '콘텐츠리움 홈페이지', '#102b3b', '#365f72', '<path d="M22 40 38 24m-11 0h11v11"/>');
console.log('Rendered project cover and three download/home buttons with real fonts and the approved vector assets.');
