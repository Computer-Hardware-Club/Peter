const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = readFileSync(join(__dirname, "clipboard.js"), "utf8");

function setup(target = { closest: () => null }) {
    const listeners = {};
    const timers = [];
    const broadcasts = {};
    const sent = [];
    let path = "/client/team";
    const client = {
        id: "team",
        clientProperties: { focused: true },
        clientState: { connectionState: "connected" },
        client: { sendKeyEvent: (...args) => sent.push(args) }
    };
    const services = {
        guacClientManager: { getManagedClientGroup: () => ({ clients: [client] }) },
        ManagedClientState: { ConnectionState: { CONNECTED: "connected" } },
        ManagedClient: { setClipboard: (recipient, data) => {
            assert.equal(recipient, client);
            sent.push([data.type, data.data]);
        } }
    };
    const clipboard = { readText: async () => "fallback" };
    const element = () => ({ append() {}, setAttribute() {}, addEventListener() {}, focus() {} });
    vm.runInNewContext(source, {
        angular: { module: () => ({ run: (registration) =>
            registration.at(-1)({ path: () => path }, { get: (name) => services[name] }, {
                $on: (name, listener) => { broadcasts[name] = listener; },
                $watch() {}
            }) }) },
        document: { activeElement: target, body: element(), createElement: element },
        navigator: { clipboard },
        window: {
            addEventListener: (name, listener, capture) => {
                assert.equal(capture, true);
                (listeners[name] ??= []).push(listener);
            },
            setTimeout: (callback) => timers.push(callback)
        }
    });

    function dispatch(type, properties) {
        const event = {
            target, metaKey: false, ctrlKey: false,
            stopImmediatePropagation() { this.stopped = true; },
            preventDefault() { this.defaultPrevented = true; },
            ...properties
        };
        for (const listener of listeners[type]) {
            listener(event);
            if (event.stopped) break;
        }
        return event;
    }

    return { clipboard, sent, dispatch,
        select: (text) => broadcasts.guacClipboard(null, { source: client.id, data: text }),
        leave: () => { path = "/"; },
        tick: async () => { for (const callback of timers.splice(0)) await callback(); } };
}

for (const modifier of ["metaKey", "ctrlKey"]) {
    for (const shiftKey of [false, true]) {
        test(`pastes exactly once with ${modifier}, shift=${shiftKey}`, async () => {
            const { dispatch, sent, tick } = setup();
            const keydown = dispatch("keydown", { [modifier]: true, shiftKey, code: "KeyV" });
            assert.equal(keydown.stopped, true);
            assert.equal(keydown.defaultPrevented, undefined);
            const text = "héllo\n世界";
            const paste = dispatch("paste", { clipboardData: { getData: () => text } });
            assert.equal(paste.defaultPrevented, true);
            await tick();
            assert.deepEqual(sent, [["text/plain", text], [1, 0xffe3], [1, 0x56], [0, 0x56], [0, 0xffe3]]);
        });
    }
}

test("uses clipboard permission as a fallback when the browser emits no paste event", async () => {
    const { dispatch, sent, tick } = setup();
    dispatch("keydown", { ctrlKey: true, shiftKey: true, code: "KeyV" });
    await tick();
    assert.deepEqual(sent[0], ["text/plain", "fallback"]);
});

test("drops an in-flight clipboard read after leaving the terminal", async () => {
    const { clipboard, dispatch, sent, tick, leave } = setup();
    let resolve;
    clipboard.readText = () => new Promise((done) => { resolve = done; });
    dispatch("keydown", { metaKey: true, code: "KeyV" });
    const reading = tick();
    leave();
    resolve("do not send");
    await reading;
    assert.deepEqual(sent, []);
});

test("pastes the complete script from Guacamole's focused input sink", () => {
    const sink = {
        matches: (selector) => selector === "body > textarea",
        style: { position: "fixed", width: "0px", height: "0px" },
        closest: () => ({})
    };
    const { dispatch, sent } = setup(sink);
    const script = "# terminal paste fixture\n".repeat(740);
    const event = dispatch("paste", { clipboardData: { getData: () => script } });
    assert.equal(event.defaultPrevented, true);
    assert.deepEqual(sent, [["text/plain", script], [1, 0xffe3], [1, 0x56], [0, 0x56], [0, 0xffe3]]);
});

test("leaves paste in editable fields alone", () => {
    const { dispatch, sent } = setup();
    const event = dispatch("paste", {
        target: { closest: () => ({}) },
        clipboardData: { getData: () => "editable field" }
    });
    assert.equal(event.defaultPrevented, undefined);
    assert.deepEqual(sent, []);
});

test("copies the terminal selection and preserves Ctrl+C for interrupt", () => {
    const { dispatch, select } = setup();
    select("terminal selection");
    assert.equal(dispatch("keydown", { ctrlKey: true, key: "c" }).stopped, undefined);
    assert.equal(dispatch("keydown", { ctrlKey: true, shiftKey: true, key: "C" }).stopped, undefined);
    assert.equal(dispatch("keydown", { metaKey: true, key: "c" }).stopped, true);
    const copied = [];
    const event = dispatch("copy", { clipboardData: { setData: (...args) => copied.push(args) } });
    assert.equal(event.defaultPrevented, true);
    assert.deepEqual(copied, [["text/plain", "terminal selection"]]);
});
