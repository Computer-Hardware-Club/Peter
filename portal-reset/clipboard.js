/* global angular */
(() => {
    "use strict";

    const CONTROL = 0xffe3;
    const UPPERCASE_V = 0x56;
    const PASTE_EVENT_GRACE_MS = 100;

    angular.module("index").run(["$location", "$injector", "$rootScope", ($location, $injector, $rootScope) => {
        const manager = $injector.get("guacClientManager");
        const ManagedClient = $injector.get("ManagedClient");
        const connected = $injector.get("ManagedClientState").ConnectionState.CONNECTED;
        const selections = new WeakMap();
        let pending;

        function focusedClient(target) {
            // Guacamole focuses an invisible textarea appended directly to the body.
            const inputSink = target?.matches?.("body > textarea") &&
                target.style.position === "fixed" && target.style.width === "0px" && target.style.height === "0px";
            if (!inputSink && target?.closest?.("input, textarea, select, [contenteditable], #guac-menu")) return null;
            const route = /^\/client\/([a-z0-9_=-]+)$/i.exec($location.path());
            if (!route) return null;
            const client = manager.getManagedClientGroup(route[1]).clients.find(
                (entry) => entry.clientProperties.focused);
            return client?.clientState.connectionState === connected ? client : null;
        }

        function paste(client, text) {
            if (!text || focusedClient(document.activeElement) !== client) return;

            // Send the clipboard stream before asking the SSH terminal to paste it.
            ManagedClient.setClipboard(client, { type: "text/plain", data: text });
            client.client.sendKeyEvent(1, CONTROL);
            client.client.sendKeyEvent(1, UPPERCASE_V);
            client.client.sendKeyEvent(0, UPPERCASE_V);
            client.client.sendKeyEvent(0, CONTROL);
        }

        window.addEventListener("keydown", (event) => {
            if (event.defaultPrevented || event.isComposing || event.altKey ||
                event.metaKey === event.ctrlKey ||
                (event.code !== "KeyV" && event.key?.toLowerCase() !== "v")) return;

            const client = focusedClient(event.target);
            if (!client) return;

            // Preserve the browser's native paste action while keeping the raw
            // shortcut away from Guacamole's keyboard handler.
            event.stopImmediatePropagation();
            if (event.repeat) {
                event.preventDefault();
                return;
            }

            const request = { client };
            pending = request;
            // Some browser/shortcut combinations do not emit a paste event.
            window.setTimeout(async () => {
                if (pending !== request || focusedClient(document.activeElement) !== client) return;
                try {
                    const text = await navigator.clipboard?.readText();
                    if (pending === request) {
                        pending = null;
                        paste(client, text);
                    }
                } catch {
                    // The browser may deny clipboard permission. A native
                    // paste event still works without that permission.
                }
            }, PASTE_EVENT_GRACE_MS);
        }, true);

        $rootScope.$on("guacClipboard", (_event, data) => {
            const client = focusedClient(document.activeElement);
            if (client && data.source === client.id && typeof data.data === "string") {
                selections.set(client, data.data);
            }
        });

        window.addEventListener("keydown", (event) => {
            if (event.defaultPrevented || event.isComposing || event.altKey ||
                event.key?.toLowerCase() !== "c" ||
                !(event.metaKey && !event.ctrlKey || event.ctrlKey && event.shiftKey && !event.metaKey)) return;
            const client = focusedClient(event.target);
            if (selections.has(client)) event.stopImmediatePropagation();
        }, true);

        window.addEventListener("copy", (event) => {
            if (event.defaultPrevented || !event.clipboardData) return;
            const text = selections.get(focusedClient(event.target));
            if (text === undefined) return;
            event.clipboardData.setData("text/plain", text);
            event.preventDefault();
            event.stopImmediatePropagation();
        }, true);

        window.addEventListener("paste", (event) => {
            if (event.defaultPrevented || !event.clipboardData) return;
            const client = focusedClient(event.target);
            if (!client) return;

            pending = null;
            event.stopImmediatePropagation();
            event.preventDefault();
            paste(client, event.clipboardData.getData("text/plain"));
        }, true);
    }]);
})();
