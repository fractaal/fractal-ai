const [wsUrl, method, paramsJson = '{}'] = process.argv.slice(2);

if (!wsUrl || !method) {
  throw new Error('Usage: cdp-call.mjs <webSocketDebuggerUrl> <method> [params-json]');
}

const params = JSON.parse(paramsJson);
const ws = new WebSocket(wsUrl);

await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, {once: true});
  ws.addEventListener('error', reject, {once: true});
});

const id = 1;
const result = await new Promise((resolve, reject) => {
  ws.addEventListener('message', ({data}) => {
    const message = JSON.parse(data);
    if (message.id !== id) return;
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  });
  ws.addEventListener('error', reject, {once: true});
  ws.addEventListener('close', () => reject(new Error('CDP WebSocket closed before responding')), {once: true});
  ws.send(JSON.stringify({id, method, params}));
});

console.log(JSON.stringify(result));
ws.close();
