// Face GET pe liveUrl-ul fiecărui proiect din src/assets/projects.json și scrie status.json la stdout.
// Rulat de .github/workflows/status.yml; rezultatul e publicat pe branch-ul "status".
import { readFile } from 'node:fs/promises';

const TIMEOUT_MS = 10_000;
const projects = JSON.parse(await readFile('src/assets/projects.json', 'utf8'));

async function check(url) {
  const started = Date.now();
  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { 'user-agent': 'otnielcodes-status-check' },
    });
    await res.body?.cancel();
    return { up: res.status < 400, code: res.status, ms: Date.now() - started };
  } catch {
    return { up: false, code: null, ms: null };
  }
}

const entries = await Promise.all(
  projects.filter((p) => p.liveUrl).map(async (p) => [p.name, await check(p.liveUrl)]),
);

for (const [name, r] of entries) {
  console.error(`${r.up ? 'UP  ' : 'DOWN'} ${name} ${r.code ?? '-'} ${r.ms ?? '-'}ms`);
}

console.log(
  JSON.stringify({ checkedAt: new Date().toISOString(), projects: Object.fromEntries(entries) }, null, 2),
);
