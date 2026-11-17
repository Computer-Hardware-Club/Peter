const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = readFileSync(join(__dirname, "reset.js"), "utf8");
const team = "workshop-ab123456-team-1-cd123456";
const resetting = team + "|resetting|abcdef123456";
const ready = team + "|ready|abcdef123456";
const states = {
    CONNECTING: "CONNECTING", CONNECTED: "CONNECTED", DISCONNECTED: "DISCONNECTED",
    CLIENT_ERROR: "CLIENT_ERROR", TUNNEL_ERROR: "TUNNEL_ERROR"
};

function element() {
    return {
        children: [],
        append(...nodes) { this.children.push(...nodes); },
        setAttribute() {},
        addEventListener(name, callback) { this[name] = callback; }
    };
}

const codes = {
    SERVER_ERROR: 0x200, SERVER_BUSY: 0x201, UPSTREAM_TIMEOUT: 0x202, UPSTREAM_ERROR: 0x203,
    RESOURCE_CLOSED: 0x206, UPSTREAM_NOT_FOUND: 0x207, UPSTREAM_UNAVAILABLE: 0x208,
    CLIENT_TIMEOUT: 0x308, CLIENT_UNAUTHORIZED: 0x301, CLIENT_FORBIDDEN: 0x303
};

function setup(initialState = states.CONNECTED, initialCode = 0) {
    const document = { createElement: element, body: element() };
    const timers = new Map();
    const watchers = [];
    const events = {};
    let sequence = 0;
    let path = "/client/first";
    let now = 0;
    let replacement;
    const fixture = { name: team, username: "1", reconnects: 0, disconnects: 0, tree: [] };
    const client = { clientState: { connectionState: initialState, statusCode: initialCode }, client: { disconnect() {
        fixture.disconnects++;
        client.clientState.connectionState = states.DISCONNECTED;
    } } };
    const auth = {
        getCurrentUsername: () => fixture.username,
        request: async (config) => {
            assert.equal(config.cache, false);
            if (config.url.endsWith("/connectionGroups/ROOT/tree")) {
                if (fixture.treeError) throw { type: fixture.treeError };
                return { childConnections: fixture.tree };
            }
            if (fixture.pendingRequest) await fixture.pendingRequest;
            if (fixture.error) throw { type: fixture.error };
            return { name: fixture.name };
        }
    };
    const root = {
        $watch: (get, listener) => watchers.push({ get, listener }),
        $on: (name, listener) => { events[name] = listener; },
        $evalAsync: (fn) => fn()
    };
    const location = { path(value) {
        if (value === undefined) return path;
        path = value;
        return this;
    }, replace() {} };
    const services = {
        authenticationService: auth,
        guacClientManager: {
            getManagedClientGroup: () => ({ clients: [replacement || client] }),
            replaceManagedClient: () => {
                fixture.reconnects++;
                replacement = { ...client, clientState: { connectionState: states.CONNECTING } };
                return replacement;
            }
        },
        ClientIdentifier: {
            Types: { CONNECTION: "c" },
            fromString: () => ({ id: "8", type: "c", dataSource: "postgresql" }),
            toString: ({ id }) => id
        },
        ManagedClientState: { ConnectionState: states }
    };
    vm.runInNewContext(source, {
        angular: { module: () => ({ run: (registration) =>
            registration.at(-1)(root, location, { get: (name) => services[name] }) }) },
        document,
        Guacamole: { Status: { Code: codes } },
        Date: class extends Date { static now() { return now; } },
        setTimeout: (fn) => { timers.set(++sequence, fn); return sequence; },
        clearTimeout: (id) => timers.delete(id)
    });
    function digest() {
        for (const watch of watchers) {
            const value = watch.get();
            if (watch.value !== value) {
                watch.value = value;
                watch.listener(value);
            }
        }
    }
    digest();
    const overlay = document.body.children[0];
    return Object.assign(fixture, {
        overlay,
        message: overlay.children[0].children[0],
        progress: overlay.children[0].children[1],
        async tick() {
            const [[id, callback]] = timers;
            timers.delete(id);
            await callback();
            digest();
        },
        advance: (ms) => { now += ms; },
        retry: () => overlay.children[0].children[2].click(),
        connected() {
            replacement.clientState.connectionState = states.CONNECTED;
            digest();
        },
        logout() {
            fixture.username = null;
            events.guacLogout();
            digest();
        },
        pending: () => timers.size,
        path: () => location.path(),
        navigate: (value) => { location.path(value); digest(); },
        setConnectionState(state, statusCode = codes.UPSTREAM_TIMEOUT) {
            Object.assign((replacement || client).clientState, { connectionState: state, statusCode });
        }
    });
}

test("reset progress disconnects the old client and automatically reconnects the same route", async () => {
    const app = setup();
    await app.tick();
    app.name = resetting;
    await app.tick();
    assert.equal(app.message.textContent, "Your VM is being reset…");
    assert.equal(app.progress.hidden, false);
    assert.equal(app.disconnects, 1);
    app.name = ready;
    await app.tick();
    assert.equal(app.reconnects, 1);
    assert.equal(app.path(), "/client/first");
    app.connected();
    assert.equal(app.overlay.hidden, true);
});

test("a session already resetting starts with progress, then reports failure", async () => {
    const app = setup();
    app.name = resetting;
    await app.tick();
    app.name = team + "|failed|abcdef123456";
    await app.tick();
    assert.match(app.message.textContent, /couldn’t be reset/);
    assert.equal(app.progress.hidden, true);
    app.logout();
    assert.equal(app.overlay.hidden, true);
    assert.equal(app.pending(), 0);
});

test("a tunnel error after connecting is recovered even without a reset marker", async () => {
    const app = setup();
    await app.tick();
    app.setConnectionState(states.TUNNEL_ERROR);
    await app.tick();
    assert.equal(app.reconnects, 1);
    assert.match(app.message.textContent, /Reconnecting your terminal/);
    app.connected();
    assert.equal(app.overlay.hidden, true);
});

test("a long reset keeps retrying and has a manual retry after the deadline", async () => {
    const app = setup();
    await app.tick();
    app.name = resetting;
    await app.tick();
    app.name = ready;
    await app.tick();
    app.advance(31000);
    await app.tick();
    assert.equal(app.reconnects, 2);
    app.advance(120000);
    await app.tick();
    assert.match(app.message.textContent, /Retry or ask/);
    app.retry();
    await app.tick();
    assert.equal(app.reconnects, 3);
});

test("a stale route recovers only to an authorized connection for the same team", async () => {
    const app = setup();
    app.error = "NOT_FOUND";
    app.tree = [
        { name: ready, identifier: "replacement" },
        { name: "workshop-ab123456-team-2-cd123457", identifier: "other-team" }
    ];
    await app.tick();
    assert.equal(app.path(), "/client/replacement");
});

test("a session that cannot read its authorized directory does not keep polling", async () => {
    const app = setup();
    app.error = "PERMISSION_DENIED";
    app.treeError = "PERMISSION_DENIED";
    await app.tick();
    assert.equal(app.pending(), 0);
    assert.equal(app.reconnects, 0);
});

for (const state of [states.TUNNEL_ERROR, states.CLIENT_ERROR]) {
    test(`recovers an authorized initial ${state} without replacing an in-flight attempt`, async () => {
        const app = setup(state, codes.SERVER_ERROR);
        await app.tick();
        assert.equal(app.reconnects, 1);
        app.advance(3000);
        await app.tick();
        assert.equal(app.reconnects, 1);
        app.setConnectionState(state, codes.UPSTREAM_TIMEOUT);
        await app.tick();
        assert.equal(app.reconnects, 2);
        app.connected();
        await app.tick();
        assert.equal(app.overlay.hidden, true);
        assert.equal(app.reconnects, 2);
    });
}

test("credential and permission failures never start or continue recovery", async () => {
    const invalid = setup(states.CLIENT_ERROR, codes.CLIENT_UNAUTHORIZED);
    await invalid.tick();
    assert.equal(invalid.reconnects, 0);
    assert.equal(invalid.overlay.hidden, true);

    const denied = setup(states.TUNNEL_ERROR, codes.SERVER_ERROR);
    await denied.tick();
    denied.setConnectionState(states.TUNNEL_ERROR, codes.CLIENT_FORBIDDEN);
    denied.advance(15000);
    await denied.tick();
    assert.equal(denied.reconnects, 1);
    assert.equal(denied.overlay.hidden, true);

    const expired = setup(states.TUNNEL_ERROR, codes.SERVER_ERROR);
    expired.error = "INVALID_CREDENTIALS";
    await expired.tick();
    assert.equal(expired.pending(), 0);
    assert.equal(expired.reconnects, 0);
});

test("ignores an in-flight recovery poll after leaving the client route", async () => {
    const app = setup(states.TUNNEL_ERROR, codes.SERVER_ERROR);
    await app.tick();
    app.advance(15000);
    let resolve;
    app.pendingRequest = new Promise((done) => { resolve = done; });
    const check = app.tick();
    app.navigate("/");
    resolve();
    await check;
    assert.equal(app.reconnects, 1);
    assert.equal(app.pending(), 0);
    assert.equal(app.overlay.hidden, true);
});
