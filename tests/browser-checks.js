"use strict";

const assert = require("node:assert/strict");
const { execFile } = require("node:child_process");
const { readFileSync } = require("node:fs");
const { createServer } = require("node:http");
const { join } = require("node:path");
const { promisify } = require("node:util");
const { chromium } = require("playwright");
const run = promisify(execFile);

async function clipboard(context) {
    const source = readFileSync(join(__dirname, "../portal-reset/clipboard.js"));
    const server = createServer((request, response) => {
        if (request.url === "/clipboard.js") {
            response.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8" }).end(source);
            return;
        }
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }).end(`<!doctype html>
            <textarea style="position:fixed;width:0;height:0"></textarea>
            <script>
            window.sent = [];
            const client = { id: "fixture", clientProperties: { focused: true },
                clientState: { connectionState: "connected" }, client: { sendKeyEvent() {} } };
            const services = { guacClientManager: { getManagedClientGroup: () => ({ clients: [client] }) },
                ManagedClient: { setClipboard: (_, data) => sent.push(data.data) },
                ManagedClientState: { ConnectionState: { CONNECTED: "connected" } } };
            window.angular = { module: () => ({ run: (registration) => registration.at(-1)(
                { path: () => "/client/fixture" }, { get: (name) => services[name] },
                { $watch: (get, change) => change(get()), $on: (_, handler) => {
                    window.selectTerminal = (data) => handler(null, { source: client.id, data });
                } }) }) };
            window.systemClipboard = navigator.clipboard;
            </script><script src="/clipboard.js"></script>`);
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const url = `http://127.0.0.1:${server.address().port}`;
    await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: url });
    const page = await context.newPage();
    const modifier = process.platform === "darwin" ? "Meta" : "Control";
    try {
        await page.goto(url);
        await page.evaluate(() => selectTerminal("real browser clipboard"));
        await page.getByRole("button", { name: "Copy selection" }).click();
        await page.getByText("Terminal selection copied.").waitFor();
        assert.equal(await page.evaluate(() => systemClipboard.readText()), "real browser clipboard");
        await page.evaluate(() => {
            Object.defineProperty(navigator, "clipboard", { value: {
                readText: async () => { throw new DOMException("Denied", "NotAllowedError"); },
                writeText: async () => { throw new DOMException("Denied", "NotAllowedError"); }
            } });
            selectTerminal("permission fallback");
        });
        await page.getByRole("button", { name: "Copy selection" }).click();
        await page.getByText("Use your browser’s Copy command to copy the selected text.").waitFor();
        await page.keyboard.press(`${modifier}+c`);
        assert.equal(await page.evaluate(() => systemClipboard.readText()), "permission fallback");
        await page.getByRole("button", { name: "Close", exact: true }).click();

        await page.locator("body > textarea").focus();
        await page.evaluate(() => systemClipboard.writeText("native paste"));
        await page.keyboard.press(`${modifier}+v`);
        await page.waitForFunction(() => sent.length === 1);
        assert.deepEqual(await page.evaluate(() => sent), ["native paste"]);

        // Suppress the native shortcut so this branch is deterministic even on browsers that implement it.
        await page.evaluate(() => document.activeElement.dispatchEvent(new KeyboardEvent("keydown", {
            key: "v", code: "KeyV", ctrlKey: true, shiftKey: true, bubbles: true
        })));
        const input = page.getByRole("textbox", { name: "Terminal clipboard text" });
        await input.waitFor();
        await input.fill("manual paste");
        await page.getByRole("button", { name: "Send to terminal" }).click();
        assert.deepEqual(await page.evaluate(() => sent), ["native paste", "manual paste"]);
    } finally {
        await page.close();
        server.close();
    }
}

async function portal(context, url) {
    const page = await context.newPage();
    let transport;
    let connections = 0;
    let received = 0;
    const failures = [];
    const labControl = process.env.PETER_LAB_CONTROL;
    page.on("pageerror", (error) => failures.push(error.message));
    await page.addInitScript(() => {
        const WebSocket = window.WebSocket;
        window.terminalCloses = [];
        window.WebSocket = class extends WebSocket {
            constructor(...args) {
                super(...args);
                this.addEventListener("close", ({ code, wasClean }) => {
                    terminalCloses.push({ time: new Date().toISOString(), code, wasClean });
                });
            }
        };
    });
    await page.routeWebSocket("**/websocket-tunnel**", (socket) => {
        transport = socket;
        connections++;
        socket.connectToServer().onMessage((payload) => {
            received += payload.length;
            socket.send(payload);
        });
    });
    const paste = page.getByRole("button", { name: "Paste text", exact: true });
    async function command(text) {
        await paste.click();
        await page.getByRole("textbox", { name: "Terminal clipboard text" }).fill(`${text}\n`);
        await page.getByRole("button", { name: "Send to terminal" }).click();
    }

    try {
        await page.goto(url);
        await page.locator('input[name="username"]').fill("1");
        await page.locator('input[type="password"]').fill("peter-review-only");
        await page.getByRole("button", { name: "Login", exact: true }).click();
        await paste.waitFor({ timeout: 30000 });
        assert.equal(connections, 1);
        const before = received;
        await command(`awk 'BEGIN {for (i=0; i<12000; i++) printf "%06d Peter terminal output %08d\\n", i, (i*472531)%100000000}' && touch /tmp/peter-output-completed`);
        const deadline = Date.now() + 90000;
        while (received - before < 16000 && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 250));
        assert.ok(received - before >= 16000, "browser should receive sustained terminal frames");
        assert.equal(connections, 1, "the output burst should not reconnect the tunnel");
        if (labControl) await run("bash", [labControl, "reserve"], { timeout: 10000 });
        await command("touch /tmp/peter-session-responsive");
        await page.waitForTimeout(1500);
        if (labControl) await run("bash", [labControl, "responsive"], { timeout: 10000 });
        console.log(JSON.stringify({ event: "output burst received", time: new Date().toISOString(), frameBytes: received - before }));

        if (labControl) await run("bash", [labControl, "interrupt"], { timeout: 10000 });
        else transport.close();
        await page.waitForFunction(() => terminalCloses.length > 0);
        const reconnectDeadline = Date.now() + 30000;
        while (connections < 2 && Date.now() < reconnectDeadline) await new Promise((resolve) => setTimeout(resolve, 250));
        await paste.waitFor({ timeout: 30000 });
        assert.ok(connections >= 2, "the client must reconnect to a fresh WebSocket");
        await command("touch /tmp/peter-reconnected");
        await page.waitForTimeout(1500);
        assert.deepEqual(failures, []);
    } finally {
        console.log(JSON.stringify({ event: "terminal WebSocket closes", closes: await page.evaluate(() => window.terminalCloses), connections }));
        await page.close();
    }
}

(async () => {
    const browser = await chromium.launch();
    try {
        const context = await browser.newContext();
        context.setDefaultTimeout(15000);
        await clipboard(context);
        if (process.env.PETER_LAB_URL) await portal(context, process.env.PETER_LAB_URL);
    } finally {
        await browser.close();
    }
})().catch((error) => { console.error(error); process.exitCode = 1; });
