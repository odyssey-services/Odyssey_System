import { addDiagnosticEntry, clearDiagnosticsEntries, subscribeDiagnostics } from "../utils/diagnostics.js";
import { normalizeError, toErrorMessage } from "../utils/errors.js";
import { escapeHtml } from "../utils/json.js";
import {
  getPlayerInfo,
  getRoomSceneContext,
  getSelectedOwlbearTokens,
  subscribePlayerChanges,
  subscribeSceneItems,
  waitForObrReady,
} from "../bridge/obrBridge.js";
import {
  loadRoomSupabaseSettings,
  saveRoomSupabaseSettings,
  clearRoomSupabaseSettings,
  hasSupabaseSettings,
  maskSupabaseApiKey,
  normalizeSupabaseSettings,
} from "../bridge/settingsBridge.js";
import { getTokenCharacterLink, setTokenCharacterLink } from "../bridge/tokenBridge.js";
import { testSupabaseConnection } from "../bridge/supabaseBridge.js";

function safeArray(value) {
  return Array.isArray(value) ? value : [];
}

function describeRole(role) {
  return role === "GM" ? "GM" : "Player";
}

function describeBucket(bucket) {
  switch (String(bucket ?? "").trim()) {
    case "player":
      return "Player";
    case "npc_template":
      return "NPC Template";
    case "npc_active":
      return "NPC Active";
    default:
      return "Unknown";
  }
}

function formatTimestamp(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString();
}

function createShellMarkup(title, subtitle, { showTokenPlacementPanel = false } = {}) {
  return `
    <header class="shell-header">
      <div>
        <h1>${escapeHtml(title)}</h1>
        <p class="shell-subtitle">${escapeHtml(subtitle)}</p>
      </div>
      <div class="shell-pill">Stage 5 Token Flow</div>
    </header>

    <section class="panel">
      <div class="panel-title">Status</div>
      <div class="status-grid">
        <div class="status-card">
          <span class="status-label">Owlbear</span>
          <strong data-field="owlbearStatus">Connecting...</strong>
        </div>
        <div class="status-card">
          <span class="status-label">Player Role</span>
          <strong data-field="playerRole">...</strong>
        </div>
        <div class="status-card">
          <span class="status-label">Supabase Settings</span>
          <strong data-field="supabaseStatus">...</strong>
        </div>
        <div class="status-card">
          <span class="status-label">Database Bridge</span>
          <strong data-field="bridgeStatus">Ready</strong>
        </div>
      </div>
      <p class="panel-note">The extension stays a thin Owlbear client: RPCs own validation, cloning, token-link records, and character state.</p>
    </section>

    <section class="panel">
      <div class="panel-title">Supabase Connection</div>
      <div class="field-grid">
        <label class="field-stack">
          <span>Supabase URL</span>
          <input data-field="supabaseUrl" type="text" placeholder="https://project.supabase.co" autocomplete="off" spellcheck="false">
        </label>
        <label class="field-stack">
          <span>Public API Key</span>
          <input data-field="supabaseKey" type="password" placeholder="sb_publishable_..." autocomplete="off" spellcheck="false">
        </label>
      </div>
      <div class="button-row">
        <button data-action="saveSettings" type="button">Save Room Settings</button>
        <button data-action="clearSettings" type="button" class="secondary">Clear</button>
        <button data-action="testConnection" type="button" class="secondary">Test Supabase Connection</button>
        <button data-action="refreshShell" type="button" class="secondary">Refresh Status</button>
      </div>
      <p class="muted" data-field="connectionHint">Room-level Supabase settings are not configured yet.</p>
    </section>

    ${showTokenPlacementPanel ? `
      <section class="panel">
        <div class="panel-title">Load Character To Selected Token</div>
        <div class="field-grid">
          <label class="field-stack">
            <span>Search Catalog</span>
            <input data-field="placementSearch" type="text" placeholder="Filter by name, key, or owner" autocomplete="off" spellcheck="false">
          </label>
          <label class="field-stack">
            <span>Character Catalog</span>
            <select data-field="placementCharacterSelect"></select>
          </label>
        </div>
        <div class="field-grid">
          <label class="field-stack">
            <span>Instance Name (Templates)</span>
            <input data-field="placementInstanceName" type="text" placeholder="Bandit 1" autocomplete="off" spellcheck="false">
          </label>
          <label class="toggle-stack">
            <span>Catalog Mode</span>
            <label class="toggle-inline">
              <input data-field="includeActiveNpc" type="checkbox">
              <span>Reattach existing active NPC</span>
            </label>
          </label>
        </div>
        <div class="list" data-field="placementSelectedToken"></div>
        <div class="list" data-field="placementSelectionInfo"></div>
        <div class="button-row">
          <button data-action="refreshPlacement" type="button" class="secondary">Refresh Placement Data</button>
          <button data-action="loadCharacterToToken" type="button">Load Into Selected Token</button>
          <button data-action="retryMetadataSync" type="button" class="secondary">Retry Metadata Sync</button>
        </div>
        <p class="muted" data-field="placementHint">GM-only token placement panel is initializing.</p>
      </section>
    ` : ""}

    <section class="panel">
      <div class="panel-title">Owlbear Context</div>
      <div class="list" data-field="contextList"></div>
    </section>

    <section class="panel">
      <div class="panel-title">Selected Tokens</div>
      <div class="list" data-field="selectedTokens"></div>
    </section>

    <section class="panel">
      <div class="panel-title">Available Bridge Modules</div>
      <div class="list" data-field="moduleList"></div>
    </section>

    <section class="panel">
      <div class="panel-title">Diagnostics</div>
      <div class="button-row">
        <button data-action="clearDiagnostics" type="button" class="secondary">Clear Diagnostics</button>
      </div>
      <div class="diagnostic-log" data-field="diagnostics"></div>
    </section>
  `;
}

function buildContextRows(state) {
  const settings = normalizeSupabaseSettings(state.settings);
  return [
    ["Room ID", state.roomContext.roomId || "Unavailable"],
    ["Scene ID", state.roomContext.sceneId || "Unavailable"],
    ["Player", state.player.name || "Unnamed player"],
    ["Selected Count", String(state.selectedTokens.length)],
    ["Supabase URL", settings.url || "Missing"],
    ["Supabase Key", settings.apiKey ? maskSupabaseApiKey(settings.apiKey) : "Missing"],
  ];
}

function buildSelectedTokenRows(tokens) {
  if (!tokens.length) {
    return '<div class="list-item"><div class="list-item-title">No tokens selected.</div><div class="muted">Select tokens on the Owlbear scene to inspect their minimal metadata links.</div></div>';
  }
  return tokens
    .map((token) => {
      const link = getTokenCharacterLink(token);
      const title = token?.name ? String(token.name) : `Token ${String(token?.id ?? "").slice(0, 8)}`;
      const details = [
        `id: ${String(token?.id ?? "").trim() || "unknown"}`,
        `character_id: ${link.characterId || "not linked"}`,
        `state_version: ${link.stateVersion}`,
        `status_summary: ${link.statusSummary || "none"}`,
      ];
      return `
        <div class="list-item">
          <div class="list-item-title">${escapeHtml(title)}</div>
          <div class="muted">${escapeHtml(details.join(" | "))}</div>
        </div>
      `;
    })
    .join("");
}

function buildModuleRows(runtime) {
  const sections = [
    ["Bridges", Object.keys(runtime.bridges ?? {})],
    ["APIs", Object.keys(runtime.api ?? {})],
    ["Constants", Object.keys(runtime.constants ?? {})],
  ];
  return sections
    .map(([label, values]) => `
      <div class="list-item">
        <div class="list-item-title">${escapeHtml(label)}</div>
        <div class="muted">${escapeHtml((values ?? []).join(", ") || "None")}</div>
      </div>
    `)
    .join("");
}

function buildDiagnosticsRows(entries) {
  if (!entries.length) {
    return '<div class="list-item"><div class="muted">No diagnostics yet.</div></div>';
  }
  return entries
    .map((entry) => `
      <div class="list-item">
        <div class="list-item-title">${escapeHtml(entry.title)}</div>
        <div class="muted">${escapeHtml(entry.level.toUpperCase())} | ${escapeHtml(formatTimestamp(entry.createdAt))}</div>
        ${entry.details ? `<pre>${escapeHtml(entry.details)}</pre>` : ""}
      </div>
    `)
    .join("");
}

function normalizeCatalogEntries(response) {
  return safeArray(response?.characters);
}

function getFilteredPlacementCatalog(state) {
  const search = state.placement.search.trim().toLowerCase();
  if (!search) return state.placement.catalog.slice();
  return state.placement.catalog.filter((entry) => {
    const haystack = [
      entry?.name,
      entry?.character_key,
      entry?.owner_player_name,
      entry?.status_summary,
    ]
      .map((value) => String(value ?? "").toLowerCase())
      .join(" ");
    return haystack.includes(search);
  });
}

function syncPlacementSelection(state) {
  const filtered = getFilteredPlacementCatalog(state);
  if (!filtered.length) {
    state.placement.selectedCharacterId = "";
    return filtered;
  }
  if (!filtered.some((entry) => entry.id === state.placement.selectedCharacterId)) {
    state.placement.selectedCharacterId = String(filtered[0]?.id ?? "");
  }
  return filtered;
}

function getSelectedCatalogCharacter(state) {
  return state.placement.catalog.find((entry) => entry.id === state.placement.selectedCharacterId) ?? null;
}

function getPlacementAction(character) {
  const bucket = String(character?.character_bucket ?? "").trim();
  switch (bucket) {
    case "player":
      return {
        label: "Bind Player",
        requestedAction: "bind_player",
      };
    case "npc_template":
      return {
        label: "Spawn NPC",
        requestedAction: "spawn_npc",
      };
    case "npc_active":
      return {
        label: "Reattach Active NPC",
        requestedAction: "reattach_active_npc",
      };
    default:
      return {
        label: "Load Into Selected Token",
        requestedAction: "",
      };
  }
}

function getTokenLinkSnapshot(tokenRealtimeSync) {
  return safeArray(tokenRealtimeSync?.getSnapshot?.()?.tokenLinks);
}

function buildPlacementTokenRows(state, tokenRealtimeSync) {
  if (state.selectedTokens.length !== 1) {
    const message = state.selectedTokens.length > 1
      ? "Select exactly one Owlbear token before loading a character."
      : "Select one existing Owlbear token on the scene first.";
    return `<div class="list-item"><div class="list-item-title">Selected Token</div><div class="muted">${escapeHtml(message)}</div></div>`;
  }

  const token = state.selectedTokens[0];
  const localLink = getTokenCharacterLink(token);
  const serverLink = getTokenLinkSnapshot(tokenRealtimeSync).find(
    (entry) => String(entry?.token_id ?? "").trim() === String(token?.id ?? "").trim(),
  );
  const rows = [
    `id: ${String(token?.id ?? "").trim() || "unknown"}`,
    `local: ${localLink.characterId || "not linked"} / v${localLink.stateVersion || 0}`,
    `server: ${serverLink?.character_id || "not linked"} / v${Number(serverLink?.state_version ?? 0) || 0}`,
  ];
  return `
    <div class="list-item">
      <div class="list-item-title">${escapeHtml(token?.name ? String(token.name) : "Selected token")}</div>
      <div class="muted">${escapeHtml(rows.join(" | "))}</div>
    </div>
  `;
}

function buildPlacementSelectionRows(state, tokenRealtimeSync) {
  const selected = getSelectedCatalogCharacter(state);
  if (!selected) {
    return '<div class="list-item"><div class="list-item-title">Catalog Selection</div><div class="muted">Refresh the catalog and choose a character to continue.</div></div>';
  }

  const action = getPlacementAction(selected);
  const linkedState = selected.linked_token_id
    ? `Linked token: ${selected.linked_token_name || selected.linked_token_id}`
    : "Not linked in this scene";
  const replaceHint = state.placement.replaceExistingTokenLink
    ? "Replacement confirmation is armed for the next load attempt."
    : "No replacement confirmation is armed.";
  const syncState = tokenRealtimeSync?.getSnapshot?.();

  return `
    <div class="list-item">
      <div class="list-item-title">${escapeHtml(selected.name || selected.character_key || "Character")}</div>
      <div class="muted">${escapeHtml([
        `bucket: ${describeBucket(selected.character_bucket)}`,
        `key: ${selected.character_key || "unknown"}`,
        `status: ${selected.status_summary || "none"}`,
        linkedState,
        syncState?.contextKey ? `sync: ${syncState.contextKey}` : "sync: idle",
        replaceHint,
      ].join(" | "))}</div>
      <div class="tag-list" style="margin-top:8px">
        <span class="tag">${escapeHtml(action.label)}</span>
      </div>
    </div>
  `;
}

function buildPlacementOptions(state) {
  const filtered = syncPlacementSelection(state);
  if (!filtered.length) {
    return '<option value="">No characters available</option>';
  }
  return filtered
    .map((entry) => `
      <option value="${escapeHtml(entry.id)}">
        ${escapeHtml(`${entry.name || entry.character_key} [${describeBucket(entry.character_bucket)}]`)}
      </option>
    `)
    .join("");
}

function buildPlacementHint(state, canManageRoomSettings, configured) {
  if (!canManageRoomSettings) {
    return "Only the GM can place or bind characters to Owlbear tokens.";
  }
  if (!configured) {
    return "Save the room Supabase URL and key first, then refresh the placement data.";
  }
  if (state.selectedTokens.length !== 1) {
    return "Select exactly one existing Owlbear token before loading a character.";
  }
  if (state.placement.loadingCatalog) {
    return "Refreshing the character catalog and current room token links.";
  }
  if (state.placement.pendingMetadataSync) {
    return "The Supabase RPC succeeded, but writing Owlbear token metadata failed. Use Retry Metadata Sync or refresh the scene state.";
  }
  if (state.placement.resultMessage) {
    return state.placement.resultMessage;
  }
  if (!state.placement.catalog.length) {
    return "Refresh the placement data to load Players, NPC Templates, and optional active NPC reattach targets.";
  }
  return state.placement.replaceExistingTokenLink
    ? "The next placement attempt will move/replace an existing link if the server requires confirmation."
    : "Choose a catalog character, then bind or spawn it into the selected Owlbear token.";
}

function buildMetadataFieldsFromResult(result) {
  return {
    stateVersion: Math.max(0, Number(result?.state?.state_version ?? 0) || 0),
    statusSummary: String(result?.state?.status_summary ?? "").trim(),
    updatedAt: String(result?.state?.updated_at ?? "").trim() || new Date().toISOString(),
  };
}

export async function mountBridgeShell({
  root,
  title,
  subtitle,
  runtime,
  globalName = "OdysseyBridge",
  features = {},
  tokenRealtimeSync = null,
}) {
  if (!(root instanceof HTMLElement)) {
    throw new Error("Shell root element is missing.");
  }

  const showTokenPlacementPanel = features?.tokenPlacement === true;

  await waitForObrReady();

  root.innerHTML = createShellMarkup(title, subtitle, { showTokenPlacementPanel });

  const refs = {
    owlbearStatus: root.querySelector('[data-field="owlbearStatus"]'),
    playerRole: root.querySelector('[data-field="playerRole"]'),
    supabaseStatus: root.querySelector('[data-field="supabaseStatus"]'),
    bridgeStatus: root.querySelector('[data-field="bridgeStatus"]'),
    supabaseUrl: root.querySelector('[data-field="supabaseUrl"]'),
    supabaseKey: root.querySelector('[data-field="supabaseKey"]'),
    connectionHint: root.querySelector('[data-field="connectionHint"]'),
    contextList: root.querySelector('[data-field="contextList"]'),
    selectedTokens: root.querySelector('[data-field="selectedTokens"]'),
    moduleList: root.querySelector('[data-field="moduleList"]'),
    diagnostics: root.querySelector('[data-field="diagnostics"]'),
    placementSearch: root.querySelector('[data-field="placementSearch"]'),
    placementCharacterSelect: root.querySelector('[data-field="placementCharacterSelect"]'),
    placementInstanceName: root.querySelector('[data-field="placementInstanceName"]'),
    includeActiveNpc: root.querySelector('[data-field="includeActiveNpc"]'),
    placementSelectedToken: root.querySelector('[data-field="placementSelectedToken"]'),
    placementSelectionInfo: root.querySelector('[data-field="placementSelectionInfo"]'),
    placementHint: root.querySelector('[data-field="placementHint"]'),
  };

  const buttons = {
    saveSettings: root.querySelector('[data-action="saveSettings"]'),
    clearSettings: root.querySelector('[data-action="clearSettings"]'),
    testConnection: root.querySelector('[data-action="testConnection"]'),
    refreshShell: root.querySelector('[data-action="refreshShell"]'),
    clearDiagnostics: root.querySelector('[data-action="clearDiagnostics"]'),
    refreshPlacement: root.querySelector('[data-action="refreshPlacement"]'),
    loadCharacterToToken: root.querySelector('[data-action="loadCharacterToToken"]'),
    retryMetadataSync: root.querySelector('[data-action="retryMetadataSync"]'),
  };

  const state = {
    ready: true,
    player: await getPlayerInfo(),
    roomContext: await getRoomSceneContext(),
    settings: await loadRoomSupabaseSettings(),
    selectedTokens: await getSelectedOwlbearTokens(),
    connectionTest: null,
    placement: {
      search: "",
      includeActiveNpc: false,
      instanceName: "",
      catalog: [],
      selectedCharacterId: "",
      loadingCatalog: false,
      actionBusy: false,
      replaceExistingTokenLink: false,
      pendingMetadataSync: null,
      resultMessage: "",
    },
  };

  function setPlacementMessage(message = "") {
    state.placement.resultMessage = String(message ?? "").trim();
  }

  function syncSettingsInputs() {
    if (refs.supabaseUrl instanceof HTMLInputElement) {
      refs.supabaseUrl.value = state.settings.url;
    }
    if (refs.supabaseKey instanceof HTMLInputElement) {
      refs.supabaseKey.value = state.settings.apiKey;
    }
    if (refs.placementSearch instanceof HTMLInputElement) {
      refs.placementSearch.value = state.placement.search;
    }
    if (refs.placementInstanceName instanceof HTMLInputElement) {
      refs.placementInstanceName.value = state.placement.instanceName;
    }
    if (refs.includeActiveNpc instanceof HTMLInputElement) {
      refs.includeActiveNpc.checked = state.placement.includeActiveNpc;
    }
  }

  function renderPlacement(canManageRoomSettings, configured) {
    if (!showTokenPlacementPanel) return;

    const filteredCatalog = syncPlacementSelection(state);
    const selectedCharacter = getSelectedCatalogCharacter(state);
    const action = getPlacementAction(selectedCharacter);
    const hasSingleToken = state.selectedTokens.length === 1;
    const canExecuteLoad = Boolean(
      canManageRoomSettings &&
      configured &&
      hasSingleToken &&
      selectedCharacter &&
      !state.placement.loadingCatalog &&
      !state.placement.actionBusy,
    );

    refs.placementSelectedToken.innerHTML = buildPlacementTokenRows(state, tokenRealtimeSync);
    refs.placementSelectionInfo.innerHTML = buildPlacementSelectionRows(state, tokenRealtimeSync);
    refs.placementHint.textContent = buildPlacementHint(state, canManageRoomSettings, configured);

    if (refs.placementCharacterSelect instanceof HTMLSelectElement) {
      refs.placementCharacterSelect.innerHTML = buildPlacementOptions(state);
      refs.placementCharacterSelect.value = filteredCatalog.some((entry) => entry.id === state.placement.selectedCharacterId)
        ? state.placement.selectedCharacterId
        : "";
      refs.placementCharacterSelect.disabled = !canManageRoomSettings || !configured || !filteredCatalog.length || state.placement.loadingCatalog || state.placement.actionBusy;
    }
    if (refs.placementSearch instanceof HTMLInputElement) {
      refs.placementSearch.disabled = !canManageRoomSettings || !configured || state.placement.loadingCatalog || state.placement.actionBusy;
    }
    if (refs.placementInstanceName instanceof HTMLInputElement) {
      refs.placementInstanceName.disabled = !canManageRoomSettings || !configured || state.placement.actionBusy;
    }
    if (refs.includeActiveNpc instanceof HTMLInputElement) {
      refs.includeActiveNpc.disabled = !canManageRoomSettings || !configured || state.placement.loadingCatalog || state.placement.actionBusy;
    }
    if (buttons.refreshPlacement instanceof HTMLButtonElement) {
      buttons.refreshPlacement.disabled = !canManageRoomSettings || !configured || state.placement.actionBusy;
    }
    if (buttons.loadCharacterToToken instanceof HTMLButtonElement) {
      buttons.loadCharacterToToken.textContent = state.placement.actionBusy
        ? "Working..."
        : action.label;
      buttons.loadCharacterToToken.disabled = !canExecuteLoad;
    }
    if (buttons.retryMetadataSync instanceof HTMLButtonElement) {
      buttons.retryMetadataSync.disabled = !canManageRoomSettings || !state.placement.pendingMetadataSync || state.placement.actionBusy;
    }
  }

  function render() {
    const role = describeRole(state.player.role);
    const configured = hasSupabaseSettings(state.settings);
    const canManageRoomSettings = state.player.role === "GM";

    refs.owlbearStatus.textContent = state.ready ? "Connected" : "Not ready";
    refs.playerRole.textContent = role;
    refs.supabaseStatus.textContent = configured ? "Configured" : "Missing";
    refs.bridgeStatus.textContent = state.connectionTest?.ok === false ? "Error" : "Ready";
    refs.connectionHint.textContent = configured
      ? `Room settings are configured. ${canManageRoomSettings ? "GM can update them here." : "Only GM can modify them."}`
      : `Room settings are missing. ${canManageRoomSettings ? "Enter URL and key, then save them to room metadata." : "Ask the GM to configure them."}`;

    refs.contextList.innerHTML = buildContextRows(state)
      .map(
        ([label, value]) => `
          <div class="list-item compact">
            <div class="list-item-title">${escapeHtml(label)}</div>
            <div class="muted">${escapeHtml(value)}</div>
          </div>
        `,
      )
      .join("");
    refs.selectedTokens.innerHTML = buildSelectedTokenRows(state.selectedTokens);
    refs.moduleList.innerHTML = buildModuleRows(runtime);
    buttons.saveSettings.disabled = !canManageRoomSettings;
    buttons.clearSettings.disabled = !canManageRoomSettings;
    refs.supabaseUrl.disabled = !canManageRoomSettings;
    refs.supabaseKey.disabled = !canManageRoomSettings;

    renderPlacement(canManageRoomSettings, configured);
  }

  const unsubscribeDiagnostics = subscribeDiagnostics((entries) => {
    refs.diagnostics.innerHTML = buildDiagnosticsRows(entries);
  });

  syncSettingsInputs();
  render();

  async function refreshSnapshot() {
    state.player = await getPlayerInfo();
    state.roomContext = await getRoomSceneContext();
    state.settings = await loadRoomSupabaseSettings();
    state.selectedTokens = await getSelectedOwlbearTokens();
    syncSettingsInputs();
    render();
  }

  async function refreshPlacementCatalog({ silent = false } = {}) {
    if (!showTokenPlacementPanel) return;
    if (state.player.role !== "GM") {
      state.placement.catalog = [];
      state.placement.selectedCharacterId = "";
      render();
      return;
    }
    if (!hasSupabaseSettings(state.settings)) {
      state.placement.catalog = [];
      state.placement.selectedCharacterId = "";
      render();
      return;
    }

    state.placement.loadingCatalog = true;
    render();
    try {
      const response = await runtime.api.placement.getCharacterSpawnCatalog(
        {
          campaign_id: state.roomContext.campaignId,
          room_id: state.roomContext.roomId,
          scene_id: state.roomContext.sceneId,
          include_active_npcs: state.placement.includeActiveNpc,
        },
        state.settings,
      );
      state.placement.catalog = normalizeCatalogEntries(response);
      syncPlacementSelection(state);
      if (!silent) {
        addDiagnosticEntry(
          "info",
          "Placement catalog refreshed",
          `Rows loaded: ${state.placement.catalog.length}`,
        );
      }
    } catch (error) {
      const normalized = normalizeError(error, "Unable to load the placement catalog.");
      state.placement.catalog = [];
      state.placement.selectedCharacterId = "";
      addDiagnosticEntry("error", "Placement catalog failed", normalized.message);
    } finally {
      state.placement.loadingCatalog = false;
      render();
    }
  }

  async function refreshPlacementData({ reason = "manual", silent = false } = {}) {
    await refreshSnapshot();
    if (tokenRealtimeSync?.reconcileNow) {
      await tokenRealtimeSync.reconcileNow(`placement:${reason}`);
    }
    await refreshPlacementCatalog({ silent });
    await refreshSnapshot();
  }

  async function retryPendingMetadataSync() {
    const pending = state.placement.pendingMetadataSync;
    if (!pending) return;
    state.placement.actionBusy = true;
    render();
    try {
      await setTokenCharacterLink(pending.tokenId, pending.characterId, pending.fields);
      state.placement.pendingMetadataSync = null;
      setPlacementMessage("Owlbear token metadata was restored successfully.");
      if (tokenRealtimeSync?.reconcileNow) {
        await tokenRealtimeSync.reconcileNow("retry-metadata-sync");
      }
      await refreshSnapshot();
    } catch (error) {
      const normalized = normalizeError(error, "Unable to retry token metadata synchronization.");
      setPlacementMessage(normalized.message);
      addDiagnosticEntry("error", "Retry metadata sync failed", normalized.message);
    } finally {
      state.placement.actionBusy = false;
      render();
    }
  }

  async function loadCharacterToSelectedToken() {
    if (state.player.role !== "GM") {
      addDiagnosticEntry("warn", "Token placement is GM-only", "Only the GM can bind or spawn characters into tokens.");
      return;
    }
    if (state.selectedTokens.length !== 1) {
      setPlacementMessage("Select exactly one Owlbear token before loading a character.");
      render();
      return;
    }

    const selectedCharacter = getSelectedCatalogCharacter(state);
    if (!selectedCharacter) {
      setPlacementMessage("Choose a catalog character first.");
      render();
      return;
    }

    const action = getPlacementAction(selectedCharacter);
    if (!action.requestedAction) {
      setPlacementMessage("The selected catalog entry cannot be loaded.");
      render();
      return;
    }

    const token = state.selectedTokens[0];
    state.placement.actionBusy = true;
    setPlacementMessage("");
    render();

    try {
      const result = await runtime.api.character.loadCharacterToToken(
        {
          source_character_id: selectedCharacter.id,
          token_id: token.id,
          token_name: token.name ?? "",
          token_layer: token.layer ?? "CHARACTER",
          campaign_id: state.roomContext.campaignId,
          room_id: state.roomContext.roomId,
          scene_id: state.roomContext.sceneId,
          instance_name: state.placement.instanceName,
          requested_action: action.requestedAction,
          replace_existing_token_link: state.placement.replaceExistingTokenLink,
          allow_rebind_active_npc: action.requestedAction === "reattach_active_npc",
        },
        state.settings,
      );

      if (result?.ok === false) {
        const retryableErrors = new Set([
          "TOKEN_ALREADY_LINKED",
          "CHARACTER_ALREADY_LINKED_IN_SCENE",
          "TOKEN_CONTEXT_MISMATCH",
        ]);
        if (retryableErrors.has(String(result?.error ?? "").trim())) {
          state.placement.replaceExistingTokenLink = true;
          setPlacementMessage(`${result.message || result.error}. Repeat the action to confirm moving/replacing the existing link.`);
          addDiagnosticEntry("warn", "Placement confirmation required", result.message || result.error || "Server requested an explicit replace confirmation.");
        } else {
          state.placement.replaceExistingTokenLink = false;
          setPlacementMessage(result.message || result.error || "Unable to load the selected character into the token.");
          addDiagnosticEntry("error", "Character load failed", result.message || result.error || "Unknown load error.");
        }
        return;
      }

      const metadataFields = buildMetadataFieldsFromResult(result);
      state.placement.replaceExistingTokenLink = false;
      state.placement.pendingMetadataSync = null;

      try {
        await setTokenCharacterLink(token.id, result?.character?.id, metadataFields);
      } catch (error) {
        state.placement.pendingMetadataSync = {
          tokenId: token.id,
          characterId: result?.character?.id,
          fields: metadataFields,
        };
        const normalized = normalizeError(error, "Supabase link was created, but Owlbear token metadata could not be written.");
        setPlacementMessage(normalized.message);
        addDiagnosticEntry("error", "Token metadata write failed", normalized.message);
      }

      if (!state.placement.pendingMetadataSync) {
        setPlacementMessage(`${action.label} completed for ${result?.character?.name || result?.character?.character_key || "character"}.`);
      }

      if (tokenRealtimeSync?.reconcileNow) {
        await tokenRealtimeSync.reconcileNow("load-character-success");
      }

      await refreshPlacementCatalog({ silent: true });
      await refreshSnapshot();
      addDiagnosticEntry(
        "info",
        "Character loaded into token",
        `${action.label}: ${result?.character?.character_key || result?.character?.id || "unknown character"}`,
      );
    } catch (error) {
      const normalized = normalizeError(error, "Unable to load the selected character into the Owlbear token.");
      state.placement.replaceExistingTokenLink = false;
      setPlacementMessage(normalized.message);
      addDiagnosticEntry("error", "Load character to token failed", normalized.message);
    } finally {
      state.placement.actionBusy = false;
      render();
    }
  }

  buttons.saveSettings.addEventListener("click", async () => {
    if (state.player.role !== "GM") {
      addDiagnosticEntry("warn", "Room settings are GM-only", "Only the GM should update room-level Supabase settings.");
      return;
    }
    try {
      state.settings = await saveRoomSupabaseSettings({
        url: refs.supabaseUrl.value,
        apiKey: refs.supabaseKey.value,
      });
      state.connectionTest = null;
      addDiagnosticEntry("info", "Room Supabase settings saved", state.settings.url || "Configured without URL.");
      render();
      if (showTokenPlacementPanel) {
        await refreshPlacementData({ reason: "settings-saved", silent: true });
      }
    } catch (error) {
      const normalized = normalizeError(error, "Unable to save room Supabase settings.");
      addDiagnosticEntry("error", normalized.name || "Save failed", normalized.message);
    }
  });

  buttons.clearSettings.addEventListener("click", async () => {
    if (state.player.role !== "GM") {
      addDiagnosticEntry("warn", "Room settings are GM-only", "Only the GM should clear room-level Supabase settings.");
      return;
    }
    try {
      state.settings = await clearRoomSupabaseSettings();
      state.connectionTest = null;
      state.placement.catalog = [];
      state.placement.selectedCharacterId = "";
      state.placement.pendingMetadataSync = null;
      syncSettingsInputs();
      addDiagnosticEntry("info", "Room Supabase settings cleared");
      if (tokenRealtimeSync?.reconcileNow) {
        await tokenRealtimeSync.reconcileNow("settings-cleared");
      }
      render();
    } catch (error) {
      addDiagnosticEntry("error", "Clear failed", toErrorMessage(error, "Unable to clear room Supabase settings."));
    }
  });

  buttons.testConnection.addEventListener("click", async () => {
    const draft = normalizeSupabaseSettings({
      url: refs.supabaseUrl.value,
      apiKey: refs.supabaseKey.value,
    });
    try {
      const result = await testSupabaseConnection(draft);
      state.connectionTest = result;
      addDiagnosticEntry(
        "info",
        "Supabase connection test passed",
        `Sample rows returned: ${result.sampleRowCount}`,
      );
      render();
    } catch (error) {
      state.connectionTest = {
        ok: false,
        message: toErrorMessage(error, "Supabase connection test failed."),
      };
      addDiagnosticEntry(
        "error",
        "Supabase connection test failed",
        state.connectionTest.message,
      );
      render();
    }
  });

  buttons.refreshShell.addEventListener("click", () => {
    void refreshSnapshot()
      .then(async () => {
        if (showTokenPlacementPanel) {
          await refreshPlacementData({ reason: "shell-refresh", silent: true });
        }
        addDiagnosticEntry("info", "Shell status refreshed");
      })
      .catch((error) => {
        addDiagnosticEntry("error", "Refresh failed", toErrorMessage(error, "Unable to refresh shell state."));
      });
  });

  buttons.clearDiagnostics.addEventListener("click", () => {
    clearDiagnosticsEntries();
  });

  if (showTokenPlacementPanel) {
    refs.placementSearch?.addEventListener("input", (event) => {
      state.placement.search = String(event.target?.value ?? "");
      syncPlacementSelection(state);
      render();
    });

    refs.placementCharacterSelect?.addEventListener("change", (event) => {
      state.placement.selectedCharacterId = String(event.target?.value ?? "").trim();
      state.placement.replaceExistingTokenLink = false;
      render();
    });

    refs.placementInstanceName?.addEventListener("input", (event) => {
      state.placement.instanceName = String(event.target?.value ?? "");
    });

    refs.includeActiveNpc?.addEventListener("change", async (event) => {
      state.placement.includeActiveNpc = Boolean(event.target?.checked);
      state.placement.replaceExistingTokenLink = false;
      await refreshPlacementCatalog({ silent: true });
    });

    buttons.refreshPlacement?.addEventListener("click", () => {
      void refreshPlacementData({ reason: "manual-refresh" })
        .then(() => {
          addDiagnosticEntry("info", "Placement data refreshed");
        })
        .catch((error) => {
          addDiagnosticEntry("error", "Placement refresh failed", toErrorMessage(error, "Unable to refresh placement data."));
        });
    });

    buttons.loadCharacterToToken?.addEventListener("click", () => {
      void loadCharacterToSelectedToken();
    });

    buttons.retryMetadataSync?.addEventListener("click", () => {
      void retryPendingMetadataSync();
    });
  }

  void subscribePlayerChanges(async (player) => {
    state.player = player;
    state.selectedTokens = await getSelectedOwlbearTokens().catch(() => state.selectedTokens);
    render();
  });

  void subscribeSceneItems(async () => {
    state.selectedTokens = await getSelectedOwlbearTokens().catch(() => state.selectedTokens);
    render();
  });

  if (showTokenPlacementPanel) {
    void refreshPlacementData({ reason: "mount", silent: true }).catch(() => {});
  }

  globalThis[globalName] = runtime;
  addDiagnosticEntry(
    "info",
    `${title} ready`,
    `Bridge shell loaded. Global runtime is available as window.${globalName}.`,
  );

  return () => {
    unsubscribeDiagnostics();
  };
}
