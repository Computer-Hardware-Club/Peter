"use strict";

const $ = (id) => document.getElementById(id);
const model = {
  mode: "loading",
  state: null,
  csrf: null,
  revision: 0,
  selected: null,
  viewRevision: 0,
  roster: new Map(),
  templateOptions: "",
  stateRequest: null,
  transcriptRequest: null,
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
  model.selected = null;
  model.viewRevision += 1;
  model.pendingAction = null;
  model.submitting = false;
  model.roster.clear();
  $("team-list").replaceChildren();
  $("terminal-output").textContent = "";
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
  const machine = String(team.status || "").toLowerCase();
  if (team.active) return { label: "In session", tone: "live" };
  if (team.ready && (!machine || machine === "running" || machine === "ready")) {
    return { label: "Ready", tone: "ready" };
  }
  if (machine === "stopped") return { label: "Stopped", tone: "offline" };
  if (machine === "error" || machine === "missing" || machine === "offline") {
    return { label: machine[0].toUpperCase() + machine.slice(1), tone: "offline" };
  }
  return { label: "Preparing", tone: "pending" };
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
    const options = templates.map((template) => new Option(template.id, template.id));
    select.replaceChildren(...options);
    if (templates.some((template) => template.id === selected)) select.value = selected;
    else if (templates.some((template) => template.id === "test-vm")) select.value = "test-vm";
    model.templateOptions = signature;
  }
  $("template-description").textContent =
    templates.find((template) => template.id === select.value)?.description || "";
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
  if (model.selected !== slot) {
    model.selected = slot;
    model.viewRevision += 1;
    $("terminal-output").textContent = "";
    $("terminal-output").className = "empty";
    $("terminal-scroll").scrollTop = 0;
  }
  renderState();
  refreshTranscript();
}

function renderTeam(team, busy) {
  $("team-detail").hidden = !team;
  if (!team) return;

  const status = teamPresentation(team);
  $("team-title").textContent = `Team ${team.slot}`;
  $("team-subtitle").textContent = team.ready
    ? `VM template · ${model.state.event.template}` : "VM access is being prepared.";
  setPill($("team-status"), status);
  $("open-credentials").disabled = !team.ready || busy;
  $("reset-team").disabled = busy;
  $("remove-team").disabled = busy;
  $("terminal-status").classList.toggle("live", Boolean(team.active));
  $("terminal-status").lastElementChild.textContent = team.active ? "Live" : "Recent";

  if (!$("terminal-output").textContent) {
    $("terminal-output").className = "empty";
    $("terminal-output").textContent = team.active ? "Waiting for terminal output…" : "No terminal output yet.";
  }
}

function renderState() {
  if (!model.state) return;
  const { event, templates, job, portal } = model.state;
  const teams = [...(event?.teams || [])].sort((left, right) => left.slot - right.slot);
  const live = teams.filter((team) => team.active).length;
  const ready = teams.filter((team) => team.ready).length;
  const busy = model.submitting || job?.state === "running";
  const nextSelected = teams.some((team) => team.slot === model.selected) ? model.selected : teams[0]?.slot ?? null;
  if (nextSelected !== model.selected) {
    model.selected = nextSelected;
    model.viewRevision += 1;
    $("terminal-output").textContent = "";
    $("terminal-scroll").scrollTop = 0;
  }

  $("workshop-title").textContent = event?.name || "Workshops";
  $("workshop-summary").textContent = event
    ? `${event.template} · ${teams.length} team${teams.length === 1 ? "" : "s"} · ${live} in session`
    : "Set up isolated VMs for your next meeting.";
  $("workshop-start").hidden = Boolean(event);
  $("active-workshop").hidden = !event;
  $("portal-link").hidden = !portal;
  if (portal) $("portal-link").href = portal;

  $("job-banner").hidden = !job && !model.submitting;
  $("job-banner").className = `notice ${job?.state || "running"}`;
  const jobMessage = model.submitting
    ? "Submitting workshop change…"
    : job?.state === "failed" ? `${job.label} failed. ${job.error || "Try again."}`
      : job?.state === "done" ? `${job.label} complete.`
        : job ? `${job.label}…` : "";
  if ($("job-message").textContent !== jobMessage) $("job-message").textContent = jobMessage;

  renderTemplates(templates || []);
  $("deploy-form").querySelector("button[type=submit]").disabled = busy || !templates?.length;
  $("add-team").disabled = busy || teams.length >= 4;
  $("end-workshop").disabled = busy;
  $("roster-summary").textContent = `${ready} of ${teams.length} ready`;
  renderRoster(teams);
  renderTeam(getTeam(), busy);
  if (model.credentials) {
    const team = getTeam(model.credentials.slot);
    if (!team?.ready || team.username !== model.credentials.username) closeCredentials();
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
      model.csrf = state.csrf || model.csrf;
      setMode("dashboard");
      renderState();
    } catch (error) {
      if (revision !== model.revision) return;
      if (error.status === 401) {
        signInScreen(model.mode === "dashboard" ? "Your session ended. Sign in again." : "");
      } else if (model.mode === "dashboard") {
        if ($("message").hidden) message("Could not refresh workshop status. Retrying…", true);
      } else {
        signInScreen("Could not connect to Peter. Try signing in again.");
      }
    }
  })();
  model.stateRequest = request;
  await request;
  if (model.stateRequest === request) model.stateRequest = null;
}

function setTranscript(text, empty) {
  const output = $("terminal-output");
  if (output.textContent === text && output.classList.contains("empty") === empty) return;
  const scroll = $("terminal-scroll");
  const follow = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 35;
  output.textContent = text;
  output.classList.toggle("empty", empty);
  if (follow) scroll.scrollTop = scroll.scrollHeight;
}

async function refreshTranscript() {
  const team = getTeam();
  if (!team || model.mode !== "dashboard" || model.transcriptRequest) return;
  const revision = model.viewRevision;
  const request = (async () => {
    try {
      const { text, storageLow } = await api(`/api/team/${team.slot}/transcript`);
      if (revision !== model.viewRevision) return;
      $("recording-warning").hidden = !storageLow;
      if (text) setTranscript(text, false);
      else setTranscript(team.active ? "Waiting for terminal output…" : "No terminal output yet.", true);
    } catch (error) {
      if (revision !== model.viewRevision) return;
      if (error.status === 401) signInScreen("Your session ended. Sign in again.");
      else if ($("terminal-output").classList.contains("empty")) {
        setTranscript("Terminal output is temporarily unavailable.", true);
      }
    }
  })();
  model.transcriptRequest = request;
  await request;
  if (model.transcriptRequest === request) model.transcriptRequest = null;
  if (revision !== model.viewRevision) refreshTranscript();
}

async function sendAction(payload) {
  if (model.submitting || model.state?.job?.state === "running") return;
  model.submitting = true;
  renderState();
  try {
    await api("/api/action", payload);
    await refreshState({ fresh: true });
    refreshTranscript();
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
    const credentials = await api(`/api/team/${slot}/credentials`);
    if (revision !== model.credentialRevision || !$("credentials-dialog").open) return;
    const current = getTeam(slot);
    if (!current?.ready || current.username !== team.username || current.username !== credentials.username) {
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
$("reset-team").addEventListener("click", () => {
  const team = getTeam();
  if (!team) return;
  const { slot, username } = team;
  confirmAction({ action: "reset", slot, username }, `Reset Team ${slot}’s VM?`,
    "This wipes the VM and starts a fresh copy from the workshop template. The team can reconnect with the same credentials.", "Wipe and reset VM");
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
    await navigator.clipboard.writeText([
      credentials.portal,
      `Username: ${credentials.username}`,
      `Password: ${credentials.password}`,
    ].join("\n"));
    if (credentials === model.credentials) $("credentials-message").textContent = "Copied the workshop link and team login.";
  } catch {
    if (credentials === model.credentials) $("credentials-message").textContent = "Select the username and password to copy them.";
  }
});

async function poll() {
  if (model.mode === "dashboard" && !document.hidden) {
    await refreshState();
    refreshTranscript();
  }
  setTimeout(poll, 2000);
}

refreshState().then(poll);
