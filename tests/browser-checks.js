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
            <textarea id="terminal" style="position:fixed;width:0;height:0"></textarea>
            <dialog open><input aria-label="Regular input" value="local text">
            <div contenteditable aria-label="Editable text">editable</div></dialog>
            <script>
            window.sent = [];
            window.keys = [];
            window.addEventListener("paste", (event) => {
                if (window.suppressPaste) {
                    window.suppressPaste = false;
                    event.preventDefault();
                    event.stopImmediatePropagation();
                }
            }, true);
            document.addEventListener("keydown", (event) => {
                if (event.code === "KeyC") keys.push({ trusted: event.isTrusted, canceled: event.defaultPrevented });
            });
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
        if (process.platform === "win32") {
            await page.locator("#terminal").focus();
            await page.keyboard.press("Control+Shift+c");
            await page.locator("#terminal").focus();
            await page.keyboard.press("Control+c");
            assert.deepEqual(await page.evaluate(() => keys), [
                { trusted: true, canceled: false }, { trusted: true, canceled: false }
            ], "Windows shortcuts must reach the terminal/browser without interception");
        }
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

        const regular = page.getByRole("textbox", { name: "Regular input" });
        await regular.selectText();
        await page.keyboard.press(`${modifier}+c`);
        assert.equal(await page.evaluate(() => systemClipboard.readText()), "local text");
        await regular.fill("");
        await page.keyboard.press(`${modifier}+v`);
        assert.equal(await regular.inputValue(), "local text");
        const editable = page.locator("[contenteditable]");
        await editable.fill("");
        await page.keyboard.press(`${modifier}+v`);
        assert.equal(await editable.textContent(), "local text");
        assert.deepEqual(await page.evaluate(() => sent), []);

        await page.locator("#terminal").focus();
        await page.evaluate(() => systemClipboard.writeText("native paste"));
        await page.keyboard.press(`${modifier}+v`);
        await page.waitForFunction(() => sent.length === 1);
        assert.deepEqual(await page.evaluate(() => sent), ["native paste"]);

        // Suppress the next native paste before the extension sees it to exercise its fallback.
        await page.evaluate(() => { window.suppressPaste = true; });
        await page.keyboard.press(`${modifier}+Shift+v`);
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
    const labControl = process.env.PETER_LAB_CONTROL;
    assert.ok(labControl, "portal checks require a disposable lab");
    const lab = (action) => run("bash", [labControl, action], { timeout: 30000 });

    async function poll(check, timeout = 30000) {
        const deadline = Date.now() + timeout;
        for (;;) {
            try {
                if (await check()) return;
            } catch (error) {
                if (Date.now() >= deadline) throw error;
            }
            assert.ok(Date.now() < deadline, "timed out waiting for terminal evidence");
            await new Promise((resolve) => setTimeout(resolve, 250));
        }
    }

    async function login(browserContext = context) {
        const page = await browserContext.newPage();
        const metrics = { connections: 0, received: 0, errors: [] };
        page.on("pageerror", (error) => metrics.errors.push(error.message));
        page.on("console", (message) => {
            if (message.text().startsWith("Workshop terminal disconnected")) console.log(message.text());
        });
        page.on("websocket", (socket) => {
            if (!socket.url().includes("/websocket-tunnel")) return;
            metrics.connections++;
            socket.on("framereceived", ({ payload }) => { metrics.received += payload.length; });
        });
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
        await page.goto(url);
        await page.locator('input[name="username"]').fill("1");
        await page.locator('input[type="password"]').fill("peter-review-only");
        await page.getByRole("button", { name: "Login", exact: true }).click();
        return { page, metrics };
    }

    await lab("outage");
    const { page, metrics } = await login();
    const paste = page.getByRole("button", { name: "Paste text", exact: true });
    const closes = () => page.evaluate(() => window.terminalCloses);
    async function command(text) {
        await paste.click();
        await page.getByRole("textbox", { name: "Terminal clipboard text" }).fill(`${text}\n`);
        await page.getByRole("button", { name: "Send to terminal" }).click();
    }

    try {
        await page.getByText("Reconnecting your terminal…", { exact: true }).waitFor();
        await poll(() => metrics.connections >= 2);
        await lab("restore");
        await paste.waitFor({ timeout: 30000 });
        await lab("dashboard-live");
        const connected = metrics.connections;
        const closed = (await closes()).length;
        const before = metrics.received;
        const connectedThroughout = async () => {
            assert.equal(metrics.connections, connected, "the terminal acquired a replacement WebSocket");
            assert.equal((await closes()).length, closed, "the terminal WebSocket closed");
        };
        await command(`awk 'BEGIN {for (i=0; i<12000; i++) printf "%06d Peter terminal output %08d\\n", i, (i*472531)%100000000}' && touch /tmp/peter-output-completed`);
        await poll(async () => {
            await lab("output-complete");
            return metrics.received - before >= 16000;
        }, 90000);
        await connectedThroughout();
        await command("touch /tmp/peter-session-responsive");
        await poll(async () => (await lab("responsive"), true));
        await connectedThroughout();
        console.log(JSON.stringify({ event: "12000-line command completed and terminal responded",
            time: new Date().toISOString(), frameBytes: metrics.received - before }));

        await lab("reserve");
        await command("printf 'exercise recording pause\\n'; touch /tmp/peter-recording-paused");
        await poll(async () => (await lab("paused"), true));
        await command("touch /tmp/peter-responsive-after-pause");
        await poll(async () => (await lab("after-pause"), true));
        await connectedThroughout();

        await lab("interrupt");
        await page.waitForFunction((count) => terminalCloses.length > count, closed);
        await paste.waitFor({ timeout: 30000 });
        await command("touch /tmp/peter-reconnected");
        await poll(async () => (await lab("probe"), true));
        await lab("dashboard-live");
        assert.equal(metrics.connections, connected + 1, "a single replacement should recover the dropped worker");
        assert.deepEqual(metrics.errors, []);
        const beforeStage = (await closes()).length;
        await lab("stage");
        assert.equal(metrics.connections, connected + 1);
        assert.equal((await closes()).length, beforeStage);
        assert.equal(await paste.isVisible(), true);
        await lab("restart-staged");
    } finally {
        console.log(JSON.stringify({ event: "terminal WebSocket closes", closes: await closes(), ...metrics }));
        await page.close();
    }

    await lab("bad-password");
    const authContext = await context.browser().newContext();
    const denied = await login(authContext);
    try {
        await poll(async () => (await lab("auth-failed"), true));
        await denied.page.waitForTimeout(4500);
        assert.equal(denied.metrics.connections, 1, "invalid SSH credentials must not retry");
        assert.equal(await denied.page.getByText("Reconnecting your terminal…").isVisible(), false);
        assert.deepEqual(denied.metrics.errors, []);
    } finally {
        console.log(JSON.stringify({ event: "authentication WebSocket closes",
            closes: await denied.page.evaluate(() => window.terminalCloses), ...denied.metrics }));
        await authContext.close();
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
