// Existing Aside authenticated loopback bridge only. No profile/key reads,
// debugging switches, new listeners, arbitrary CDP methods, or persisted tokens.
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';

const { values } = parseArgs({ options: {
  native: { type: 'string' }, ws: { type: 'string' },
  icon: { type: 'string' }, version: { type: 'boolean' },
} });
const origin = 'http://localhost:45103';
const require = createRequire(import.meta.url);

function check(condition, message) { if (!condition) throw new Error(message); }

async function json(path, options = {}) {
  const response = await fetch(origin + path, {
    ...options, redirect: 'error', signal: AbortSignal.timeout(10_000),
  });
  check(response.ok, `Aside bridge ${path} returned HTTP ${response.status}`);
  const text = await response.text();
  check(text.length < 262_144, 'Aside bridge returned an oversized response');
  try { return JSON.parse(text); } catch { throw new Error('Aside bridge returned invalid JSON'); }
}

async function main() {
  check(values.native && values.ws, '--native and --ws are required');
  check(Boolean(values.icon) !== Boolean(values.version), 'Select exactly one of --icon or --version');
  const binding = require(values.native);
  check(typeof binding.run === 'function', 'First-party module does not export run');
  const challenge = await json('/json/challenge');
  check(typeof challenge.challengeId === 'string' && challenge.challengeId.length > 0, 'No challenge ID');
  check(typeof challenge.challenge === 'string' && Buffer.from(challenge.challenge, 'base64').length === 32,
    'Aside challenge must contain 32 bytes');
  let signed;
  try { signed = JSON.parse(binding.run('cdp-sign', JSON.stringify({ challenge: challenge.challenge }))); }
  catch { throw new Error('First-party cdp-sign did not return valid JSON'); }
  check(!signed.error && typeof signed.signature === 'string' && signed.signature.length > 0,
    'First-party cdp-sign failed; Aside must initialize its own install key first');
  const session = await json('/json/auth/session', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ challengeId: challenge.challengeId, signedChallenge: signed.signature }),
  });
  check(session.token_type === 'AsideSessionToken' && typeof session.access_token === 'string'
    && session.access_token.length > 0 && session.access_token.length < 8192
    && /^[!-~]+$/.test(session.access_token), 'Invalid Aside session token');
  const authorization = `AsideSessionToken ${session.access_token}`;
  const version = await json('/json/version', { headers: { Authorization: authorization } });
  check(typeof version.webSocketDebuggerUrl === 'string', 'No authenticated browser socket');
  const endpoint = new URL(version.webSocketDebuggerUrl);
  check(endpoint.protocol === 'ws:' && ['localhost', '127.0.0.1', '[::1]'].includes(endpoint.hostname)
    && endpoint.port === '45103' && endpoint.pathname.startsWith('/devtools/browser')
    && !endpoint.username && !endpoint.password, 'Refusing non-loopback or unexpected browser socket');
  const WebSocket = require(values.ws);
  const method = values.version ? 'Browser.getVersion' : 'Browser.setDockTile';
  let params = {};
  if (!values.version) {
    const png = await readFile(values.icon);
    check(png.length > 32 && png.length < 10_000_000 && png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
      'The icon input must be a bounded PNG image');
    params = { image: png.toString('base64') };
  }
  const result = await new Promise((resolve, reject) => {
    const socket = new WebSocket(endpoint.href, { headers: { Authorization: authorization }, handshakeTimeout: 10_000 });
    const timeout = setTimeout(() => { socket.terminate(); reject(new Error('Aside CDP command timed out')); }, 15_000);
    let settled = false;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket.close();
      if (error) reject(error); else resolve(result);
    };
    socket.on('open', () => socket.send(JSON.stringify({ id: 1, method, params })));
    socket.on('error', () => finish(new Error('Authenticated Aside WebSocket connection failed')));
    socket.on('close', () => { if (!settled) finish(new Error('Aside WebSocket closed before replying')); });
    socket.on('message', data => {
      let response;
      try { response = JSON.parse(data.toString()); } catch { return finish(new Error('Invalid CDP response')); }
      if (response.id !== 1) return;
      if (response.error) return finish(new Error(`${method} was rejected by Aside`));
      finish(null, response.result);
    });
  });
  // Only the version result or a command acknowledgment is printable. Authentication
  // material is never returned, written to disk, or included in exception messages.
  process.stdout.write(JSON.stringify(values.version ? result : { ok: true, method }) + '\n');
}

main().catch(error => {
  process.stderr.write(`Aside icon client: ${error.message}\n`);
  process.exitCode = 1;
});
