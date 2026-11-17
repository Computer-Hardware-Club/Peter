/* global angular, Guacamole */
(() => {
    "use strict";

    const TEAM = /^[a-z][a-z0-9-]{0,23}-[a-f0-9]{8}-team-([1-4])(?:-[a-f0-9]{8})?(?:\|(resetting|ready|failed)\|([a-f0-9]{12}))?$/;
    const POLL_MS = 1500;
    const RECONNECT_MS = 120000;
    const ATTEMPT_MS = 15000;

    angular.module("index").run(["$rootScope", "$location", "$injector", ($rootScope, $location, $injector) => {
        const auth = $injector.get("authenticationService");
        const manager = $injector.get("guacClientManager");
        const ClientIdentifier = $injector.get("ClientIdentifier");
        const states = $injector.get("ManagedClientState").ConnectionState;
        const terminalStates = [states.DISCONNECTED, states.CLIENT_ERROR, states.TUNNEL_ERROR];
        const codes = Guacamole.Status.Code;
        const transientCodes = new Set([
            codes.SERVER_ERROR, codes.SERVER_BUSY, codes.UPSTREAM_TIMEOUT, codes.UPSTREAM_ERROR,
            codes.RESOURCE_CLOSED, codes.UPSTREAM_NOT_FOUND, codes.UPSTREAM_UNAVAILABLE,
            codes.CLIENT_TIMEOUT
        ]);

        const overlay = document.createElement("div");
        const panel = document.createElement("div");
        const message = document.createElement("p");
        const progress = document.createElement("progress");
        const retry = document.createElement("button");
        const signOut = document.createElement("button");
        overlay.className = "chc-vm-reset";
        overlay.hidden = true;
        panel.className = "chc-vm-reset__panel";
        message.setAttribute("role", "status");
        progress.setAttribute("aria-label", "Terminal recovery progress");
        retry.type = "button";
        retry.textContent = "Retry connection";
        retry.addEventListener("click", () => {
            if (current?.phase === "timed-out" && stillCurrent(current)) beginReconnect(current, current.reason);
        });
        signOut.type = "button";
        signOut.textContent = "Sign out";
        signOut.addEventListener("click", () => $rootScope.$evalAsync(() => auth.logout().catch(() => {})));
        panel.append(message, progress, retry, signOut);
        overlay.append(panel);
        document.body.append(overlay);

        let current;
        let timer;

        function status(text = "", busy = false, canRetry = false) {
            overlay.hidden = !text;
            if (message.textContent !== text) message.textContent = text;
            progress.hidden = !busy;
            retry.hidden = !canRetry;
            signOut.hidden = !text;
        }

        function target() {
            const username = auth.getCurrentUsername();
            const client = /^\/client\/([a-z0-9_=-]+)$/i.exec($location.path());
            return username && client ? username + "\0" + client[1] : null;
        }

        function stillCurrent(context) {
            return current === context && target() === context.target;
        }

        function stop() {
            clearTimeout(timer);
            current = null;
            status();
        }

        function parseName(name, username) {
            const match = TEAM.exec(name);
            if (!match || (username !== match[1] && username !== match[0].split("|", 1)[0])) return null;
            return { state: match[2], generation: match[3] || null };
        }

        function request(context, resource) {
            // Guacamole's connectionService caches metadata. Reset status needs a fresh read.
            return auth.request({
                method: "GET",
                cache: false,
                timeout: 5000,
                headers: { "Cache-Control": "no-cache" },
                url: "api/session/data/" + encodeURIComponent(context.dataSource) + "/" + resource
            });
        }

        async function recoverOldUrl(context) {
            const group = await request(context, "connectionGroups/ROOT/tree");
            if (!stillCurrent(context)) return;
            const choices = (group.childConnections || []).filter((connection) =>
                parseName(connection.name, context.username));
            const replacement = choices.length === 1 && choices[0].identifier !== context.id ? choices[0] : null;
            $rootScope.$evalAsync(() => {
                if (!stillCurrent(context)) return;
                const path = replacement ? "/client/" + ClientIdentifier.toString({
                    id: replacement.identifier,
                    type: ClientIdentifier.Types.CONNECTION,
                    dataSource: context.dataSource
                }) : "/";
                $location.path(path).replace();
            });
        }

        function beginReconnect(context, reason) {
            Object.assign(context, { phase: "reconnecting", reason, deadline: Date.now() + RECONNECT_MS,
                retryAt: 0, attemptDeadline: 0, attempts: 0 });
        }

        function reconnect(context, client) {
            status(context.reason === "reset" ? "Connecting to your fresh VM…" : "Reconnecting your terminal…", true);
            const now = Date.now();
            if (now >= context.deadline) {
                context.phase = "timed-out";
                status("Couldn’t reconnect to your VM. Retry or ask a workshop officer for help.", false, true);
                return;
            }
            if (now < context.retryAt) return;
            if (!terminalStates.includes(client?.clientState.connectionState) && now < context.attemptDeadline) return;

            manager.replaceManagedClient(context.clientId);
            context.retryAt = now + Math.min(15000, POLL_MS * 2 ** context.attempts++);
            context.attemptDeadline = now + ATTEMPT_MS;
            $rootScope.$evalAsync(() => {});
        }

        function update(context, marker) {
            const changed = context.generation !== undefined && marker.generation !== context.generation;
            context.generation = marker.generation;
            const client = manager.getManagedClientGroup(context.clientId).clients[0];
            const state = client?.clientState.connectionState;
            const terminal = terminalStates.includes(state);
            const transient = state === states.DISCONNECTED
                ? context.connected || context.phase === "reconnecting"
                : transientCodes.has(client?.clientState.statusCode);

            if (marker.state === "resetting" || marker.state === "failed") {
                if (changed || context.phase !== marker.state) {
                    context.phase = marker.state;
                    status(marker.state === "resetting" ? "Your VM is being reset…" :
                        "Your VM couldn’t be reset. Ask a workshop officer for help.", marker.state === "resetting");
                    client?.client.disconnect();
                }
                return;
            }
            if (marker.state === "ready" && (changed || context.phase === "resetting" || context.phase === "failed")) {
                beginReconnect(context, "reset");
            } else if (state === states.CONNECTED) {
                context.connected = true;
                context.phase = "idle";
                status();
                return;
            } else if (terminal && !transient) {
                // Guacamole can show the original error (including SSH authentication errors).
                context.phase = "idle";
                status();
                return;
            } else if (context.phase === "idle" && terminal) {
                beginReconnect(context, "disconnect");
            }
            if (context.phase === "reconnecting") reconnect(context, client);
        }

        async function check(context) {
            try {
                const connection = await request(context, "connections/" + encodeURIComponent(context.id));
                if (!stillCurrent(context)) return;
                const marker = parseName(connection.name, context.username);
                if (marker) {
                    context.confirmed = true;
                    update(context, marker);
                }
            } catch (error) {
                if (!stillCurrent(context)) return;
                if (error.type === "NOT_FOUND" || error.type === "PERMISSION_DENIED") {
                    try {
                        await recoverOldUrl(context);
                    } catch (treeError) {
                        // If even the root directory is denied, the session cannot recover this URL.
                        if (["PERMISSION_DENIED", "UNAUTHORIZED", "INVALID_CREDENTIALS"].includes(treeError.type)) {
                            if (stillCurrent(context)) stop();
                            return;
                        }
                    }
                } else if (error.type === "UNAUTHORIZED" || error.type === "INVALID_CREDENTIALS") {
                    stop();
                    return;
                }
            } finally {
                if (stillCurrent(context)) timer = setTimeout(() => check(context), POLL_MS);
            }
        }

        $rootScope.$watch(target, (value) => {
            stop();
            if (!value) return;
            const [username, clientId] = value.split("\0");
            const { id, type, dataSource } = ClientIdentifier.fromString(clientId);
            if (type !== ClientIdentifier.Types.CONNECTION || dataSource !== "postgresql" || !/^\d+$/.test(id)) return;
            current = { target: value, username, clientId, id, dataSource, phase: "idle" };
            const context = current;
            timer = setTimeout(() => check(context), 0);
        });
        $rootScope.$watch(() => current && manager.getManagedClientGroup(current.clientId).clients[0]?.clientState.connectionState, (state) => {
            if (!current || !stillCurrent(current)) return;
            if (state === states.CONNECTED) {
                current.connected = true;
                if (current.phase === "reconnecting" || current.phase === "timed-out") {
                    current.phase = "idle";
                    status();
                }
            } else if (terminalStates.includes(state) && current.confirmed && current.phase === "idle") {
                const client = manager.getManagedClientGroup(current.clientId).clients[0];
                console.info("Workshop terminal disconnected", { time: new Date().toISOString(), state,
                    statusCode: client?.clientState.statusCode });
            }
        });
        $rootScope.$on("guacLogout", stop);
    }]);
})();
