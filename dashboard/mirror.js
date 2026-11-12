"use strict";

// Replay the same graphical instructions that Guacamole sent to the team.
// The tunnel never connects or sends messages and has no input handlers.
class ScreenMirror {
  constructor(element = null) {
    this.element = null;
    this.observer = new ResizeObserver(() => this.fit());
    this.onframe = null;
    this.reset();
    this.mount(element);
  }

  mount(element) {
    if (element === this.element && this.display.getElement().parentNode === element) return;
    this.observer.disconnect();
    this.display.getElement().remove();
    this.element = element;
    if (element) {
      element.append(this.display.getElement());
      this.observer.observe(element);
      this.fit();
    }
  }

  reset() {
    if (this.client) {
      this.client.onsync = null;
      this.client.disconnect();
      this.display.getElement().remove();
    }
    this.token = null;
    this.offset = 0;
    this.hasFrame = false;
    this.decoder = new TextDecoder();
    this.parser = new Guacamole.Parser();

    const tunnel = new Guacamole.Tunnel();
    tunnel.connect = tunnel.sendMessage = tunnel.disconnect = () => {};
    const client = new Guacamole.Client(tunnel);
    const display = client.getDisplay();
    this.client = client;
    this.display = display;
    display.getElement().setAttribute("aria-hidden", "true");
    display.showCursor(false);
    display.onresize = () => this.fit();
    client.onsync = () => {
      if (this.hasFrame) return;
      // Wait until pending drawing tasks have reached the canvas before exposing it.
      display.flush(() => {
        if (this.client !== client || this.hasFrame || !display.getWidth() || !display.getHeight()) return;
        this.hasFrame = true;
        this.onframe?.();
      });
    };
    this.parser.oninstruction = (opcode, args) => {
      if (opcode !== "audio") tunnel.oninstruction(opcode, args);
    };
    client.connect();
    if (this.element) this.element.append(display.getElement());
    this.fit();
  }

  apply(recording) {
    if (!recording.token) {
      if (this.token) this.reset();
      return;
    }

    const bytes = Uint8Array.from(atob(recording.data), (value) => value.charCodeAt(0));
    if (recording.token !== this.token || recording.offset - bytes.length !== this.offset) this.reset();
    try {
      this.parser.receive(this.decoder.decode(bytes, { stream: true }));
    } catch (error) {
      this.reset();
      throw error;
    }
    this.token = recording.token;
    this.offset = recording.offset;
  }

  fit() {
    if (!this.element) return;
    const width = this.display.getWidth();
    const height = this.display.getHeight();
    const scale = Math.min(this.element.clientWidth / width, this.element.clientHeight / height);
    if (Number.isFinite(scale) && scale > 0) this.display.scale(scale);
  }

  destroy() {
    this.mount(null);
    this.client.onsync = null;
    this.client.disconnect();
    this.client = null;
    this.onframe = null;
  }
}
