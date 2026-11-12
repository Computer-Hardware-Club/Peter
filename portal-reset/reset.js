/* global angular */
(() => {
    "use strict";

    const TEAM = /^[a-z][a-z0-9-]{0,23}-[a-f0-9]{8}-team-([1-4])(?:-[a-f0-9]{8})?(?:\|(resetting|ready|failed)\|([a-f0-9]{12}))?$/;
    const POLL_MS = 1500;
    const RECONNECT_MS = 30000;
    const ATTEMPT_MS = 8000;

    angular.module("index").run(["$rootScope", "$location", "$injector", ($rootScope, $location, $injector) => {
        const auth = $injector.get("authenticationService");
        const manager = $injector.get("guacClientManager");
        const ClientIdentifier = $injector.get("ClientIdentifier");
        const states = $injector.get("ManagedClientState").ConnectionState;
        const terminalStates = [states.DISCONNECTED, states.CLIENT_ERROR, states.TUNNEL_ERROR];

        const overlay = document.createElement("div");
        const panel = document.createElement("div");
        const message = document.createElement("p");
        const progress = document.createElement("progress");
        const signOut = document.createElement("button");
        overlay.className = "chc-vm-reset";
        overlay.hidden = true;
        panel.className = "chc-vm-reset__panel";
        message.setAttribute("role", "status");
        progress.setAttribute("aria-label", "VM reset progress");
        signOut.type = "button";
        signOut.textContent = "Sign out";
        signOut.addEventListener("click", () => $rootScope.$evalAsync(() => auth.logout().catch(() => {})));
        panel.append(message, progress, signOut);
        overlay.append(panel);
        document.body.append(overlay);

        let current;
        let timer;

        function status(text = "", busy = false) {
            overlay.hidden = !text;
            if (message.textContent !== text) message.textContent = text;
            progress.hidden = !busy;
            signOut.hidden = busy || !text;
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

        function reconnect(context) {
            status("Connecting to your fresh VM…", true);
            const now = Date.now();
            const replacementState = context.replacement?.clientState.connectionState;
            if (replacementState === states.CONNECTED) {
                context.phase = "idle";
                status();
                return;
            }
            if (now >= context.deadline) {
                context.phase = "timed-out";
                status("Couldn’t reconnect to your VM. Ask a workshop officer for help.");
                return;
            }
            if (now < context.retryAt) return;
            if (replacementState && !terminalStates.includes(replacementState) && now < context.attemptDeadline) return;

            context.replacement = manager.replaceManagedClient(context.clientId);
            context.retryAt = now + POLL_MS;
            context.attemptDeadline = now + ATTEMPT_MS;
            $rootScope.$evalAsync(() => {});
        }

        function update(context, marker) {
            const changed = context.generation !== undefined && marker.generation !== context.generation;
            context.generation = marker.generation;

            if (marker.state === "resetting" || marker.state === "failed") {
                if (changed || context.phase !== marker.state) {
                    context.phase = marker.state;
                    status(marker.state === "resetting" ? "Your VM is being reset…" :
                        "Your VM couldn’t be reset. Ask a workshop officer for help.", marker.state === "resetting");
                    const client = manager.getManagedClientGroup(context.clientId).clients[0];
                    client?.client.disconnect();
                }
                return;
            }
            if (marker.state !== "ready") return;

            if (changed || context.phase === "resetting" || context.phase === "failed") {
                context.phase = "reconnecting";
                context.deadline = Date.now() + RECONNECT_MS;
                context.retryAt = 0;
                context.replacement = null;
            }
            if (context.phase === "reconnecting") reconnect(context);
        }

        async function check(context) {
            try {
                const connection = await request(context, "connections/" + encodeURIComponent(context.id));
                if (!stillCurrent(context)) return;
                const marker = parseName(connection.name, context.username);
                if (marker) update(context, marker);
            } catch (error) {
                if (!stillCurrent(context)) return;
                if (error.type === "NOT_FOUND" || error.type === "PERMISSION_DENIED") {
                    try {
                        await recoverOldUrl(context);
                    } catch (treeError) {
                        // If even the root directory is denied, the session cannot recover this URL.
                        if (treeError.type === "PERMISSION_DENIED" || treeError.type === "INVALID_CREDENTIALS") {
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
        $rootScope.$watch(() => current?.replacement?.clientState.connectionState, (state) => {
            if (state === states.CONNECTED && current?.phase === "reconnecting" && stillCurrent(current)) {
                current.phase = "idle";
                status();
            }
        });
        $rootScope.$on("guacLogout", stop);
    }]);
})();
