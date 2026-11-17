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
        let copying;

        function activeClient() {
            const route = /^\/client\/([a-z0-9_=-]+)$/i.exec($location.path());
            if (!route) return null;
            const client = manager.getManagedClientGroup(route[1]).clients.find(
                (entry) => entry.clientProperties.focused);
            return client?.clientState.connectionState === connected ? client : null;
        }

        function focusedClient(target) {
            // Guacamole focuses an invisible textarea appended directly to the body.
            const inputSink = target?.matches?.("body > textarea") &&
                target.style.position === "fixed" && target.style.width === "0px" && target.style.height === "0px";
            if (!inputSink && target?.closest?.("input, textarea, select, button, [contenteditable], dialog, [role=dialog], #guac-menu, .chc-clipboard")) return null;
            return activeClient();
        }

        function button(label, onClick) {
            const element = document.createElement("button");
            element.type = "button";
            element.textContent = label;
            element.addEventListener("click", onClick);
            return element;
        }

        const tools = document.createElement("div");
        const panel = document.createElement("div");
        const message = document.createElement("p");
        const input = document.createElement("textarea");
        let panelClient;
        tools.className = "chc-clipboard";
        tools.hidden = true;
        panel.hidden = true;
        message.setAttribute("role", "status");
        input.setAttribute("aria-label", "Terminal clipboard text");

        function close() {
            panel.hidden = true;
            input.value = "";
            panelClient = null;
        }

        function show(client, text, selection) {
            if (activeClient() !== client) return;
            panelClient = client;
            panel.hidden = false;
            message.textContent = text;
            input.hidden = selection === undefined;
            input.readOnly = typeof selection === "string";
            input.value = selection ?? "";
            send.hidden = selection !== null;
            if (!input.hidden) {
                input.focus();
                if (input.readOnly) input.select();
            }
        }

        function manualPaste(client) {
            show(client, "Paste or type your text here, then choose Send to terminal.", null);
        }

        const copy = button("Copy selection", async () => {
            const client = activeClient();
            if (!client) return;
            const text = selections.get(client);
            if (!text) {
                show(client, "Select text in the terminal first.");
                return;
            }
            try {
                await navigator.clipboard.writeText(text);
                show(client, "Terminal selection copied.");
            } catch {
                show(client, "Use your browser’s Copy command to copy the selected text.", text);
            }
        });
        const pasteButton = button("Paste text", () => {
            const client = activeClient();
            if (client) manualPaste(client);
        });
        const send = button("Send to terminal", () => {
            if (!input.value || activeClient() !== panelClient) return;
            paste(panelClient, input.value);
            close();
            pasteButton.focus();
        });
        panel.append(message, input, send, button("Close", () => {
            close();
            pasteButton.focus();
        }));
        tools.append(copy, pasteButton, panel);
        document.body.append(tools);
        $rootScope.$watch(activeClient, (client) => {
            pending = null;
            close();
            tools.hidden = !client;
        });

        function paste(client, text) {
            if (!text || activeClient() !== client) return;

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
                if (pending !== request) return;
                if (focusedClient(document.activeElement) !== client) {
                    pending = null;
                    return;
                }
                let text;
                try {
                    text = await navigator.clipboard?.readText();
                } catch {
                    // Clipboard permission is optional. The editable field also supports native paste.
                }
                if (pending !== request) return;
                pending = null;
                if (focusedClient(document.activeElement) !== client) return;
                if (text) paste(client, text);
                else manualPaste(client);
            }, PASTE_EVENT_GRACE_MS);
        }, true);

        $rootScope.$on("guacClipboard", (_event, data) => {
            const client = activeClient();
            if (client && data.source === client.id && typeof data.data === "string") {
                selections.set(client, data.data);
            }
        });

        window.addEventListener("keydown", (event) => {
            copying = null;
            if (event.defaultPrevented || event.isComposing || event.altKey ||
                event.key?.toLowerCase() !== "c" || !event.metaKey || event.ctrlKey || event.shiftKey) return;
            const client = focusedClient(event.target);
            if (!selections.has(client)) return;
            copying = client;
            event.stopImmediatePropagation();
        }, true);

        window.addEventListener("copy", (event) => {
            const client = copying;
            copying = null;
            if (event.defaultPrevented || !event.clipboardData) return;
            if (client !== focusedClient(event.target)) return;
            const text = selections.get(client);
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
