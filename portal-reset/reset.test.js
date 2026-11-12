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
        addEventListener() {}
    };
}

function setup() {
    const document = { createElement: element, body: element() };
    const timers = new Map();
    const watchers = [];
    const events = {};
    let sequence = 0;
    let path = "/client/first";
    let replacement;
    const fixture = { name: team, username: "1", reconnects: 0, disconnects: 0, tree: [] };
    const client = { clientState: { connectionState: states.CONNECTED }, client: { disconnect() {
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
        },
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
        setConnectionState: (state) => { client.clientState.connectionState = state; }
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

test("a normal disconnection does not trigger a reset reconnect", async () => {
    const app = setup();
    app.name = ready;
    await app.tick();
    app.setConnectionState(states.DISCONNECTED);
    await app.tick();
    assert.equal(app.reconnects, 0);
    assert.equal(app.overlay.hidden, true);
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
