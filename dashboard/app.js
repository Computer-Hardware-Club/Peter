"use strict";

const $ = (id) => document.getElementById(id);
const model = {
  mode: "loading",
  state: null,
  csrf: null,
  revision: 0,
  selected: null,
  roster: new Map(),
  allTerminals: false,
  tiles: new Map(),
  screens: new Map(),
  stateStale: false,
  templateOptions: "",
  stateRequest: null,
  submitting: false,
  pendingAction: null,
  credentials: null,
  credentialRevision: 0,
  toastTimer: null,
};

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function api(path, body) {
  const options = { credentials: "same-origin", cache: "no-store", signal: AbortSignal.timeout(20000) };
  if (body !== undefined) {
    options.method = "POST";
    options.headers = { "Content-Type": "application/json" };
    if (model.csrf) options.headers["X-CSRF-Token"] = model.csrf;
    options.body = JSON.stringify(body);
  }
  const response = await fetch(path, options);
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    throw new RequestError(response.status, result?.error || `Request failed (${response.status}).`);
  }
  return result || {};
}

function setMode(mode) {
  model.mode = mode;
  $("loading").hidden = mode !== "loading";
  $("signin").hidden = mode !== "signin";
  $("dashboard").hidden = mode !== "dashboard";
  $("logout").hidden = mode !== "dashboard";
}

function setFormMessage(element, message, success = false) {
  element.textContent = message;
  element.hidden = !message;
  element.classList.toggle("success", success);
}

function message(text, error = false) {
  const notice = $("message");
  notice.textContent = text;
  notice.hidden = !text;
  notice.classList.toggle("error", error);
  clearTimeout(model.toastTimer);
  if (text) model.toastTimer = setTimeout(() => { notice.hidden = true; }, 5500);
}

function signInScreen(error = "") {
  model.revision += 1;
  model.csrf = null;
  model.state = null;
  model.stateStale = false;
  model.selected = null;
  model.allTerminals = false;
  model.pendingAction = null;
  model.submitting = false;
  model.roster.clear();
  model.tiles.clear();
  for (const entry of model.screens.values()) entry.mirror.destroy();
  model.screens.clear();
  $("team-list").replaceChildren();
  $("terminal-grid").replaceChildren();
  $("team-terminal").querySelector(".terminal-screen").replaceChildren();
  $("main").classList.remove("wall-mode");
  $("job-message").textContent = "";
  $("workshop-title").textContent = "Workshops";
  $("workshop-summary").textContent = "";
  $("team-title").textContent = "";
  $("team-subtitle").textContent = "";
  $("team-status").textContent = "";
  closeCredentials();
  if ($("confirm-dialog").open) $("confirm-dialog").close("cancel");
  $("confirm-title").textContent = "";
  $("confirm-copy").textContent = "";
  $("dashboard-password").value = "";
  setMode("signin");
  setFormMessage($("login-error"), error);
  $("dashboard-password").focus();
}

function getTeam(slot = model.selected) {
  return model.state?.event?.teams.find((team) => team.slot === slot);
}

function teamPresentation(team) {
  if (team.resetting) return { label: "Resetting", tone: "pending" };
  if (team.error) return { label: "Needs retry", tone: "offline" };
  if (model.stateStale) return { label: "Unknown", tone: "offline" };
  const machine = String(team.status || "").toLowerCase();
  if (team.active) return { label: "In session", tone: "live" };
  if (team.ready) return { label: "Ready", tone: "ready" };
  if (machine === "unknown") return { label: "Unknown", tone: "offline" };
  if (team.provisioned && machine === "running") return { label: "VM running", tone: "offline" };
  if (!team.provisioned && model.state.job?.state === "running") {
    return { label: "Preparing", tone: "pending" };
  }
  if (machine === "stopped") return { label: "Stopped", tone: "offline" };
  if (machine === "error" || machine === "missing" || machine === "offline") {
    return { label: machine[0].toUpperCase() + machine.slice(1), tone: "offline" };
  }
  return { label: "Pending", tone: "pending" };
}

function setPill(element, status) {
  element.textContent = status.label;
  element.className = `pill ${status.tone}`;
}

function renderTemplates(templates) {
  const select = $("template");
  const signature = JSON.stringify(templates);
  if (model.templateOptions !== signature) {
    const selected = select.value;
    const options = templates.map((template) => new Option(template.label || template.id, template.id));
    select.replaceChildren(...options);
    if (templates.some((template) => template.id === selected)) select.value = selected;
    else if (templates.some((template) => template.id === "base")) select.value = "base";
    model.templateOptions = signature;
  }
  const template = templates.find((option) => option.id === select.value);
  $("template-description").textContent = template?.description || "";
  const count = $("team-count");
  const limit = template?.teamLimit || 4;
  for (const option of count.options) option.disabled = Number(option.value) > limit;
  if (Number(count.value) > limit) count.value = String(limit);
}

function renderRoster(teams) {
  const list = $("team-list");
  const slots = new Set(teams.map((team) => team.slot));
  for (const [slot, item] of model.roster) {
    if (!slots.has(slot)) {
      item.button.remove();
      model.roster.delete(slot);
    }
  }

  for (const [index, team] of teams.entries()) {
    let item = model.roster.get(team.slot);
    if (!item) {
      const button = document.createElement("button");
      button.className = "team-choice";
      button.type = "button";
      button.setAttribute("aria-controls", "team-detail");
      button.addEventListener("click", () => chooseTeam(team.slot));
      const name = document.createElement("strong");
      name.textContent = `Team ${team.slot}`;
      const badge = document.createElement("span");
      button.append(name, badge);
      item = { button, badge };
      model.roster.set(team.slot, item);
    }
    if (list.children[index] !== item.button) {
      list.insertBefore(item.button, list.children[index] || null);
    }
    item.button.setAttribute("aria-pressed", String(model.selected === team.slot));
    setPill(item.badge, teamPresentation(team));
  }
}

function chooseTeam(slot) {
  model.selected = slot;
  renderState();
  refreshScreens();
}

function renderTeam(team, busy) {
  $("team-detail").hidden = !team;
  if (!team) return;

  const status = teamPresentation(team);
  $("team-title").textContent = `Team ${team.slot}`;
  $("team-subtitle").textContent = team.error || `VM template · ${model.state.event.template}`;
  setPill($("team-status"), status);
  $("open-credentials").disabled = !team.ready || model.stateStale;
  $("reset-team").textContent = team.provisioned ? "Reset VM" : "Retry VM";
  $("reset-team").disabled = busy;
  $("remove-team").disabled = busy;
}

function renderState() {
  if (!model.state) return;
  const { event, templates, job, portal } = model.state;
  const teams = [...(event?.teams || [])].sort((left, right) => left.slot - right.slot);
  const live = teams.filter((team) => team.active).length;
  const ready = teams.filter((team) => team.ready).length;
  const sessionUnknown = model.stateStale || teams.some((team) => team.active === null);
  const busy = model.stateStale || model.submitting || job?.state === "running";
  if (!getTeam()) model.selected = teams[0]?.slot ?? null;
  if (!teams.length) model.allTerminals = false;
  const wall = model.allTerminals;
  $("main").classList.toggle("wall-mode", wall);
  $("workshop-heading").hidden = wall;
  $("terminal-wall").hidden = !wall;

  $("workshop-title").textContent = event?.name || "Workshops";
  $("workshop-summary").textContent = event
    ? `${event.template} · ${teams.length} team${teams.length === 1 ? "" : "s"} · ${sessionUnknown ? "Session status unknown" : `${live} in session`}`
    : "Set up isolated VMs for your next meeting.";
  $("workshop-start").hidden = Boolean(event) || wall;
  $("active-workshop").hidden = !event || wall;
  $("portal-link").hidden = !portal;
  if (portal) $("portal-link").href = portal;
  const warning = model.stateStale ? "Could not refresh workshop status. Retrying…" : (model.state.warnings || []).join(" ");
  $("service-warning").hidden = !warning;
  if ($("service-warning").textContent !== warning) $("service-warning").textContent = warning;

  $("job-banner").hidden = wall || (!job && !model.submitting);
  $("job-banner").className = `notice ${job?.state || "running"}`;
  const jobMessage = model.submitting
    ? "Submitting workshop change…"
    : job?.state === "failed" ? `${job.label} failed. ${job.error || "Try again."}`
      : job?.state === "done" ? `${job.label} complete.`
        : job ? `${job.label}…` : "";
  if ($("job-message").textContent !== jobMessage) $("job-message").textContent = jobMessage;

  renderTemplates(templates || []);
  $("deploy-form").querySelector("button[type=submit]").disabled = busy || !templates?.length;
  $("add-team").disabled = busy || teams.length >= (event?.teamLimit || 4);
  $("open-terminals").disabled = !teams.length;
  $("end-workshop").disabled = busy;
  $("roster-summary").textContent = model.stateStale ? "Status unknown" : `${ready} of ${teams.length} ready`;
  renderRoster(teams);
  renderTeam(getTeam(), busy);
  syncTerminalTiles(teams);
  renderScreens();
  if (model.credentials) {
    const team = getTeam(model.credentials.slot);
    if (model.stateStale || !team?.ready || team.username !== model.credentials.team) closeCredentials();
  }
}

async function refreshState({ fresh = false } = {}) {
  if (model.stateRequest) {
    if (!fresh) return model.stateRequest;
    await model.stateRequest;
  }
  const revision = model.revision;
  const request = (async () => {
    try {
      const state = await api("/api/state");
      if (revision !== model.revision) return;
      model.state = state;
      model.stateStale = false;
      model.csrf = state.csrf || model.csrf;
      setMode("dashboard");
      renderState();
    } catch (error) {
      if (revision !== model.revision) return;
      if (error.status === 401) {
        signInScreen(model.mode === "dashboard" ? "Your session ended. Sign in again." : "");
      } else if (model.mode === "dashboard") {
        model.stateStale = true;
        renderState();
      } else {
        signInScreen("Could not connect to Peter. Try signing in again.");
      }
    }
  })();
  model.stateRequest = request;
  await request;
  if (model.stateRequest === request) model.stateRequest = null;
}

function syncTerminalTiles(teams) {
  const grid = $("terminal-grid");
  const identities = new Set(teams.map((team) => team.username));
  for (const [username, tile] of model.tiles) {
    if (!identities.has(username)) {
      tile.remove();
      model.tiles.delete(username);
      model.screens.get(username)?.mirror.destroy();
      model.screens.delete(username);
    }
  }
  for (const [index, team] of teams.entries()) {
    const entry = model.screens.get(team.username);
    if (entry && entry.generation !== team.screenGeneration) {
      entry.mirror.destroy();
      model.screens.delete(team.username);
    }
    let tile = model.tiles.get(team.username);
    if (!tile) {
      tile = $("terminal-tile").content.firstElementChild.cloneNode(true);
      tile.querySelector("h3").textContent = `Team ${team.slot}`;
      tile.querySelector(".terminal-scroll").setAttribute("aria-label", `Team ${team.slot} terminal screen`);
      model.tiles.set(team.username, tile);
    }
    if (grid.children[index] !== tile) grid.insertBefore(tile, grid.children[index] || null);
  }
  grid.dataset.count = teams.length;
}

function renderTerminal(panel, team) {
  const entry = model.screens.get(team.username);
  const mount = panel.querySelector(".terminal-screen");
  const empty = panel.querySelector(".terminal-empty");
  const status = panel.querySelector(".terminal-status");
  const active = !model.stateStale && team.active === true;
  const unavailable = model.stateStale || team.active === null || entry?.failed;
  const hasFrame = Boolean(entry?.mirror.hasFrame);
  const label = team.resetting ? "Resetting" : unavailable ? (hasFrame ? "Stale" : "Unavailable")
    : entry?.more ? "Catching up" : active ? (hasFrame ? "Live" : "Connecting") : (hasFrame ? "Recent" : "Idle");
  status.textContent = label;
  status.className = `terminal-status ${label.toLowerCase()}`;
  if (panel.dataset.username !== team.username) {
    model.screens.get(panel.dataset.username)?.mirror.mount(null);
    mount.replaceChildren();
    panel.dataset.username = team.username;
  }
  if (entry) entry.mirror.mount(mount);
  empty.hidden = hasFrame && !team.resetting;
  empty.textContent = team.resetting ? "Waiting for the fresh VM…" : unavailable ? "Terminal screen unavailable."
    : active ? "Waiting for the team’s screen…" : "No session yet.";
}

function renderScreens() {
  if (model.allTerminals) {
    const teams = model.state.event.teams;
    for (const team of teams) renderTerminal(model.tiles.get(team.username), team);
    $("wall-recording-warning").hidden = !teams.some((team) => model.screens.get(team.username)?.storageLow);
  } else if (getTeam()) {
    const team = getTeam();
    renderTerminal($("team-terminal"), team);
    $("team-terminal").querySelector(".recording-warning").hidden = !model.screens.get(team.username)?.storageLow;
  }
}

function teamPath(team, resource) {
  return `/api/team/${team.slot}/${encodeURIComponent(team.username)}/${resource}`;
}

async function refreshScreen(team) {
  if (team.resetting) return;
  const { username, slot, screenGeneration } = team;
  let entry = model.screens.get(username);
  if (entry?.loading) return;
  if (!entry) {
    entry = { mirror: new ScreenMirror(document.createElement("div")), generation: screenGeneration };
    entry.mirror.onframe = renderScreens;
    model.screens.set(username, entry);
  }
  const current = () => model.screens.get(username) === entry && getTeam(slot)?.username === username;
  entry.loading = true;
  try {
    // Bound each team's replay work per poll even while the recording grows.
    for (let count = 0; count < 4; count++) {
      const query = new URLSearchParams({ offset: entry.mirror.offset });
      if (entry.mirror.token) query.set("token", entry.mirror.token);
      const result = await api(`${teamPath(team, "screen")}?${query}`);
      if (!current()) return;
      if (result.team !== username || result.generation !== screenGeneration) return;
      entry.mirror.apply(result);
      Object.assign(entry, { storageLow: result.storageLow, more: result.more, failed: false });
      if (!result.more || document.hidden || (!model.allTerminals && model.selected !== slot)) break;
    }
  } catch (error) {
    if (!current()) return;
    if (error.status === 401) {
      signInScreen("Your session ended. Sign in again.");
      return;
    }
    entry.failed = true;
  } finally {
    entry.loading = false;
    if (current()) renderScreens();
  }
}

function refreshScreens() {
  if (model.mode !== "dashboard" || document.hidden) return;
  if (model.allTerminals) {
    for (const team of model.state.event.teams) refreshScreen(team);
  } else if (getTeam()) {
    refreshScreen(getTeam());
  }
}

async function sendAction(payload) {
  if (model.stateStale || model.submitting || model.state?.job?.state === "running") return;
  model.submitting = true;
  renderState();
  try {
    await api("/api/action", payload);
    await refreshState({ fresh: true });
    refreshScreens();
  } catch (error) {
    if (error.status === 401) signInScreen("Your session ended. Sign in again.");
    else message(error.message, true);
  } finally {
    model.submitting = false;
    renderState();
  }
}

function confirmAction(payload, title, copy, submit) {
  const dialog = $("confirm-dialog");
  model.pendingAction = payload;
  $("confirm-title").textContent = title;
  $("confirm-copy").textContent = copy;
  $("confirm-submit").textContent = submit;
  dialog.returnValue = "";
  dialog.showModal();
}

function resetCredentialView() {
  model.credentialRevision += 1;
  model.credentials = null;
  $("credentials-content").hidden = true;
  $("credentials-title").textContent = "";
  $("credentials-message").textContent = "";
  $("team-username").textContent = "";
  $("team-password").textContent = "";
}

function closeCredentials() {
  if ($("credentials-dialog").open) $("credentials-dialog").close();
  resetCredentialView();
}

async function openCredentials(slot) {
  const team = getTeam(slot);
  if (!team?.ready) return;
  resetCredentialView();
  const revision = model.credentialRevision;
  $("credentials-title").textContent = `Team ${slot} credentials`;
  $("credentials-message").textContent = "Loading team credentials…";
  $("credentials-dialog").showModal();
  try {
    const credentials = await api(teamPath(team, "credentials"));
    if (revision !== model.credentialRevision || !$("credentials-dialog").open) return;
    const current = getTeam(slot);
    if (model.stateStale || !current?.ready || current.username !== team.username || current.username !== credentials.team) {
      $("credentials-message").textContent = "The team changed. Close this window and open its credentials again.";
      return;
    }
    model.credentials = { ...credentials, slot };
    $("credentials-message").textContent = "Share these details privately with this team.";
    $("team-username").textContent = credentials.username;
    $("team-password").textContent = credentials.password;
    $("credentials-content").hidden = false;
  } catch (error) {
    if (revision !== model.credentialRevision) return;
    if (error.status === 401) signInScreen("Your session ended. Sign in again.");
    else $("credentials-message").textContent = error.message;
  }
}

$("login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = $("dashboard-password");
  const button = event.currentTarget.querySelector("button[type=submit]");
  if (button.disabled) return;
  button.disabled = true;
  setFormMessage($("login-error"), "");
  try {
    const result = await api("/api/login", { password: input.value });
    input.value = "";
    model.revision += 1;
    model.csrf = result.csrf;
    await refreshState({ fresh: true });
  } catch (error) {
    input.value = "";
    setFormMessage($("login-error"), error.message);
    input.focus();
  } finally {
    button.disabled = false;
  }
});

$("logout").addEventListener("click", async () => {
  try {
    await api("/api/logout", {});
    signInScreen();
  } catch (error) {
    if (error.status === 401) signInScreen();
    else message(error.message, true);
  }
});

$("template").addEventListener("change", () => renderTemplates(model.state?.templates || []));
$("deploy-form").addEventListener("submit", (event) => {
  event.preventDefault();
  sendAction({
    action: "deploy",
    name: $("workshop-name").value,
    template: $("template").value,
    teams: Number($("team-count").value),
  });
});
$("add-team").addEventListener("click", () => sendAction({ action: "add", run: model.state.event.run }));
$("open-terminals").addEventListener("click", () => {
  model.allTerminals = true;
  renderState();
  $("close-terminals").focus();
  refreshScreens();
});
$("close-terminals").addEventListener("click", () => {
  model.allTerminals = false;
  renderState();
  $("open-terminals").focus();
  refreshScreens();
});
$("reset-team").addEventListener("click", () => {
  const team = getTeam();
  if (!team) return;
  const { slot, username } = team;
  const title = team.provisioned ? `Reset Team ${slot}’s VM?` : `Retry Team ${slot}’s VM?`;
  confirmAction({ action: "reset", slot, username }, title,
    "This replaces the VM with a fresh copy from the workshop template and keeps the team’s login details.",
    team.provisioned ? "Wipe and reset VM" : "Retry VM");
});
$("remove-team").addEventListener("click", () => {
  const team = getTeam();
  if (!team) return;
  const { slot, username } = team;
  confirmAction({ action: "remove", slot, username }, `Remove Team ${slot}?`,
    "This deletes the team’s VM and revokes its portal credentials.", "Remove team");
});
$("end-workshop").addEventListener("click", () => {
  confirmAction({ action: "destroy", run: model.state.event.run }, "End this workshop?",
    "This removes every team VM and revokes their portal credentials.", "End workshop");
});
$("confirm-dialog").addEventListener("submit", (event) => {
  const action = model.pendingAction;
  model.pendingAction = null;
  if (event.submitter?.value === "confirm" && action) sendAction(action);
});
$("confirm-dialog").addEventListener("cancel", () => { model.pendingAction = null; });

$("open-credentials").addEventListener("click", () => openCredentials(model.selected));
$("credentials-dialog").addEventListener("submit", (event) => {
  if (event.target.method === "dialog") resetCredentialView();
});
$("credentials-dialog").addEventListener("cancel", resetCredentialView);
$("copy-credentials").addEventListener("click", async () => {
  const credentials = model.credentials;
  if (!credentials) return;
  try {
    await navigator.clipboard.writeText(credentials.password);
    if (credentials === model.credentials) $("credentials-message").textContent = "Password copied.";
  } catch {
    if (credentials === model.credentials) $("credentials-message").textContent = "Select the password to copy it.";
  }
});

async function poll() {
  if (model.mode === "dashboard" && !document.hidden) {
    await refreshState();
  }
  setTimeout(poll, 2000);
}

refreshState().then(() => {
  refreshScreens();
  setInterval(refreshScreens, 850);
  poll();
});
