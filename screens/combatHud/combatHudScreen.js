import hudStyles from "./combatHudStyles.css";
import { escapeHtml } from "../../utils/json.js";
import { createCombatHudStore } from "../../hud/core/combatHudStore.js";
import { createSupabaseCombatHudAdapter } from "../../hud/adapters/supabaseCombatHudAdapter.js";
import {
  selectHudMode,
  selectCurrentEntity,
  selectCombatSession,
  selectVisibleStatuses,
  selectModifierChips,
  selectTargetView,
  selectCompactBattleLog,
  selectQuickSlots,
  selectSkillById,
  selectActionLabel,
  selectPlayerStatusLabel,
  selectDisabledReason,
  selectCurrentActionCost,
} from "../../hud/core/combatHudSelectors.js";

const esc = (value) => escapeHtml(value ?? "");
const arr = (value) => (Array.isArray(value) ? value : []);
const dash = (value) => (value === null || value === undefined || value === "" ? "-" : value);
const signed = (value) => {
  const number = Number(value ?? 0) || 0;
  return `${number >= 0 ? "+" : ""}${number}`;
};

function injectStylesOnce() {
  if (document.getElementById("combat-hud-screen-styles")) return;
  const style = document.createElement("style");
  style.id = "combat-hud-screen-styles";
  style.textContent = hudStyles;
  document.head.appendChild(style);
}

export function mountCombatHudScreen({ root, runtime }) {
  injectStylesOnce();

  const adapter = createSupabaseCombatHudAdapter({ runtime });
  const store = createCombatHudStore({ adapter });
  let state = store.getState();

  root.innerHTML = `
    <div class="combat-hud-screen">
      <section class="combat-hud-banner">
        <div class="combat-hud-banner-title">
          <span>Combat HUD</span>
          <div class="combat-hud-toolbar">
            <button class="combat-hud-button secondary" type="button" data-hud-action="collapse">Collapse</button>
            <button class="combat-hud-button secondary" type="button" data-hud-action="refresh">Refresh</button>
          </div>
        </div>
        <div class="combat-hud-banner-meta" data-hud-ref="meta"></div>
      </section>
      <div data-hud-ref="body"></div>
    </div>
  `;

  const refs = {
    meta: root.querySelector('[data-hud-ref="meta"]'),
    body: root.querySelector('[data-hud-ref="body"]'),
  };

  function renderMeta() {
    const mode = selectHudMode(state);
    const session = selectCombatSession(state);
    const viewerRole = String(state?.viewer?.role || "player").toUpperCase();
    const chips = [
      chip(`Source ${state?.source || "supabase"}`),
      chip(`Role ${viewerRole}`),
      chip(`State ${mode}`, chipKindForMode(mode)),
      chip(`Selected token ${state?.selectedTokenId ? "linked" : "none"}`),
      chip(`Combat ${session?.status || "inactive"}`),
    ];
    refs.meta.innerHTML = chips.join("");
  }

  function renderBody() {
    const mode = selectHudMode(state);
    if (mode === "collapsed") {
      refs.body.innerHTML = `
        <section class="combat-hud-empty">
          HUD collapsed. Use <strong>Collapse</strong> again to reopen it.
        </section>
      `;
      return;
    }
    if (mode === "loading" || mode === "idle") {
      refs.body.innerHTML = `<section class="combat-hud-empty">Loading HUD state...</section>`;
      return;
    }
    if (mode === "error") {
      refs.body.innerHTML = `
        <section class="combat-hud-empty">
          <div>HUD failed to load.</div>
          <div style="margin-top:8px">${esc(state?.error?.message || "Unknown error")}</div>
          ${state?.error?.cause ? `<div style="margin-top:6px;color:#ffb3b3">${esc(state.error.cause)}</div>` : ""}
        </section>
      `;
      return;
    }
    if (mode === "empty") {
      refs.body.innerHTML = `
        <section class="combat-hud-empty">
          Select a linked token to preview the Combat HUD.
        </section>
      `;
      return;
    }

    const entity = selectCurrentEntity(state);
    const statuses = selectVisibleStatuses(state, 6);
    const modifiers = selectModifierChips(state);
    const target = selectTargetView(state);
    const actionLabel = selectActionLabel(state);
    const actionCost = selectCurrentActionCost(state);
    const disabledReason = selectDisabledReason(state);
    const quickSlots = selectQuickSlots(state);
    const logEntries = selectCompactBattleLog(state);
    const session = selectCombatSession(state);
    const primaryWeapon = state?.snapshot?.weapon?.primary ?? null;

    refs.body.innerHTML = `
      <div class="combat-hud-layout">
        <div class="combat-hud-column">
          ${renderPlayerPanel(entity, statuses, session)}
          ${renderTargetPanel(target)}
        </div>
        <div class="combat-hud-column">
          ${renderWeaponPanel(primaryWeapon)}
          ${renderSkillsPanel(quickSlots)}
        </div>
        <div class="combat-hud-column">
          ${renderModifiersPanel(modifiers)}
          ${renderActionPanel(actionLabel, actionCost, disabledReason)}
          ${renderLogPanel(logEntries)}
        </div>
      </div>
    `;
  }

  function renderPlayerPanel(entity, statuses, session) {
    if (!entity) {
      return panel("Player", `<div class="combat-hud-empty">No visible character runtime.</div>`);
    }

    const playerStatus = selectPlayerStatusLabel(state);
    const zones = arr(entity.zones).map((zone) => {
      const armor = arr(entity.armorByZone).find((entry) => entry.zoneId === zone.id) ?? null;
      const meta = [
        chip(zone.state),
        armor ? chip(`Armor ${dash(armor.protection)}`) : "",
        armor && armor.maxDurability ? chip(`Dur ${dash(armor.durability)}/${dash(armor.maxDurability)}`) : "",
      ].filter(Boolean).join("");
      return `
        <div class="combat-hud-zone ${esc(zone.state)}">
          <div class="combat-hud-zone-top">
            <div class="combat-hud-zone-name">${esc(zone.label)}</div>
            <div class="combat-hud-zone-state">${esc(zone.canBeTargeted ? "targetable" : "locked")}</div>
          </div>
          <div class="combat-hud-zone-meta">${meta}</div>
        </div>
      `;
    }).join("");

    const statusList = statuses.shown.length
      ? `<div class="combat-hud-status-list">${statuses.shown.map(renderStatusItem).join("")}</div>`
      : `<div class="combat-hud-empty">No active statuses.</div>`;

    return panel(
      "Player",
      `
        <div class="combat-hud-player-header">
          <div>
            <div class="combat-hud-player-name">${esc(entity.summary?.name || "Unknown")}</div>
            <div class="combat-hud-player-subtitle">
              ${esc(entity.summary?.characterType || "character")} - ${esc(playerStatus)}
            </div>
          </div>
          <div class="combat-hud-inline">
            ${chip(entity.flags?.alive ? "Alive" : "Dead", entity.flags?.alive ? "ok" : "err")}
            ${chip(entity.flags?.conscious ? "Conscious" : "Unconscious", entity.flags?.conscious ? "ok" : "warn")}
            ${chip(`Round ${dash(session?.round)}`)}
          </div>
        </div>
        <div class="combat-hud-status-grid">
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Shield</div>
            <div class="combat-hud-stat-value">${dash(entity.shield?.current)}/${dash(entity.shield?.max)}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Psi / Energy</div>
            <div class="combat-hud-stat-value">${dash(entity.psi?.current)}/${dash(entity.psi?.max)}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Main Action</div>
            <div class="combat-hud-stat-value">${entity.actions?.main ? "Ready" : "Spent"}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Move Action</div>
            <div class="combat-hud-stat-value">${entity.actions?.move ? "Ready" : "Spent"}</div>
          </div>
        </div>
        <div class="combat-hud-zones">${zones || `<div class="combat-hud-empty">No body zones.</div>`}</div>
        <div style="margin-top:12px">
          <div class="combat-hud-panel-title" style="margin-bottom:8px">Statuses</div>
          ${statusList}
          ${statuses.overflow > 0 ? `<div class="combat-hud-item-detail">+${statuses.overflow} more statuses hidden</div>` : ""}
        </div>
      `,
    );
  }

  function renderTargetPanel(target) {
    if (!target?.hasTarget) {
      return panel("Target", `<div class="combat-hud-target-empty">Pick a target on the map to populate this block.</div>`);
    }
    return panel(
      "Target",
      `
        <div class="combat-hud-item-title">${esc(target.name || "Target")}</div>
        <div class="combat-hud-item-subtitle">Kind: ${esc(target.kind || "unknown")}</div>
        <div class="combat-hud-status-grid" style="margin-top:12px">
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Body Part</div>
            <div class="combat-hud-stat-value">${esc(target.bodyPartLabel || "-")}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Mode</div>
            <div class="combat-hud-stat-value">Token Target</div>
          </div>
        </div>
      `,
    );
  }

  function renderWeaponPanel(weapon) {
    if (!weapon) {
      return panel("Weapon", `<div class="combat-hud-empty">No weapon state available.</div>`);
    }

    const fireModes = arr(weapon.fireModes).length ? arr(weapon.fireModes).join(", ") : "None";
    const reserveCount = arr(weapon.reserveMagazines).length;
    const loadedMagazine = weapon.loadedMagazine
      ? `${dash(weapon.loadedMagazine.current)}/${dash(weapon.loadedMagazine.max)} ${esc(weapon.loadedMagazine.ammoType || "")}`
      : "Not loaded";

    return panel(
      "Gun",
      `
        <div class="combat-hud-item-title">${esc(weapon.name || "Weapon")}</div>
        <div class="combat-hud-item-subtitle">Modes: ${esc(fireModes)}</div>
        <div class="combat-hud-status-grid" style="margin-top:12px">
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Magazine</div>
            <div class="combat-hud-stat-value">${loadedMagazine}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Reserve</div>
            <div class="combat-hud-stat-value">${dash(reserveCount)}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Ammo Pool</div>
            <div class="combat-hud-stat-value">${dash(weapon.ammo?.current)}/${dash(weapon.ammo?.max)}</div>
          </div>
          <div class="combat-hud-stat">
            <div class="combat-hud-stat-label">Reload</div>
            <div class="combat-hud-stat-value">${weapon.canReload ? "Available" : "Blocked"}</div>
          </div>
        </div>
      `,
    );
  }

  function renderSkillsPanel(quickSlots) {
    const items = arr(quickSlots).map((slot) => {
      const skill = selectSkillById(state, slot.skillId);
      if (!skill) {
        return `
          <div class="combat-hud-skill-item">
            <div>
              <div class="combat-hud-item-title">Slot ${slot.index + 1}</div>
              <div class="combat-hud-item-subtitle">Empty or unresolved quick action.</div>
            </div>
            ${chip(`Slot ${slot.index + 1}`)}
          </div>
        `;
      }
      return `
        <div class="combat-hud-skill-item">
          <div>
            <div class="combat-hud-item-title">${esc(skill.name)}</div>
            <div class="combat-hud-item-subtitle">${esc(skill.type)} - ${esc(skill.source)}</div>
            <div class="combat-hud-skill-meta">
              ${chip(skill.actionCost || "MAIN")}
              ${skill.resourceCost ? chip(`${esc(skill.resourceCost.type)} ${dash(skill.resourceCost.amount)}`) : ""}
              ${skill.cooldownTurns ? chip(`CD ${dash(skill.cooldownTurns)}`) : ""}
              ${skill.disabledReason ? chip(skill.disabledReason, "warn") : chip("Ready", "ok")}
            </div>
          </div>
          ${chip(`Q${slot.index + 1}`)}
        </div>
      `;
    }).join("");

    return panel(
      "Skills",
      items || `<div class="combat-hud-empty">No quick-slot actions configured.</div>`,
    );
  }

  function renderModifiersPanel(modifiers) {
    const content = arr(modifiers).length
      ? arr(modifiers).map((modifier) => `
          <div class="combat-hud-modifier-item">
            <div class="combat-hud-item-title">${esc(modifier.name)}</div>
            <div class="combat-hud-item-subtitle">${esc(modifier.source || modifier.kind || "modifier")}</div>
            <div class="combat-hud-inline" style="margin-top:8px">
              ${chip(`Value ${signed(modifier.value)}`, modifier.polarity === "negative" ? "err" : modifier.polarity === "positive" ? "ok" : "")}
              ${chip(modifier.kind || "active")}
            </div>
            ${modifier.description ? `<div class="combat-hud-item-detail">${esc(modifier.description)}</div>` : ""}
          </div>
        `).join("")
      : `<div class="combat-hud-empty">No modifiers detected.</div>`;
    return panel("Modifiers", `<div class="combat-hud-modifier-list">${content}</div>`);
  }

  function renderActionPanel(actionLabel, actionCost, disabledReason) {
    return panel(
      "Action",
      `
        <div class="combat-hud-action">
          <button class="combat-hud-action-button combat-hud-button" type="button" disabled>${esc(actionLabel)}</button>
          <div class="combat-hud-action-hint">Action cost: ${esc(actionCost || "MAIN")}</div>
          <div class="combat-hud-action-hint ${disabledReason ? "err" : ""}">
            ${esc(disabledReason || "Read-only HUD preview. Action execution stays in Resolve Attack for now.")}
          </div>
        </div>
      `,
    );
  }

  function renderLogPanel(entries) {
    const content = arr(entries).length
      ? arr(entries).map((entry) => `
          <div class="combat-hud-log-item">
            <div class="combat-hud-item-title">${esc(entry.summary || entry.action || "Log entry")}</div>
            <div class="combat-hud-item-subtitle">${esc(entry.detail || entry.target || "")}</div>
          </div>
        `).join("")
      : `<div class="combat-hud-empty">Combat log is empty.</div>`;
    return panel("Battle Log", `<div class="combat-hud-log-list">${content}</div>`);
  }

  function renderStatusItem(item) {
    return `
      <div class="combat-hud-status-item">
        <div class="combat-hud-item-title">${esc(item.name || item.id || "Status")}</div>
        <div class="combat-hud-item-subtitle">${esc(item.description || item.polarity || "")}</div>
      </div>
    `;
  }

  function panel(title, content) {
    return `
      <section class="combat-hud-panel">
        <div class="combat-hud-panel-title">${esc(title)}</div>
        ${content}
      </section>
    `;
  }

  function chip(label, kind = "") {
    return `<span class="combat-hud-chip ${esc(kind)}">${esc(label)}</span>`;
  }

  function chipKindForMode(mode) {
    if (mode === "ready") return "ok";
    if (mode === "error") return "err";
    if (mode === "empty") return "warn";
    return "";
  }

  function render() {
    renderMeta();
    renderBody();
  }

  const unsubscribe = store.subscribe((nextState) => {
    state = nextState;
    render();
  });

  root.addEventListener("click", async (event) => {
    const action = event.target?.closest?.("[data-hud-action]")?.dataset?.hudAction;
    if (!action) return;
    if (action === "collapse") {
      store.setHudCollapsed(!state?.ui?.isHudCollapsed);
      return;
    }
    if (action === "refresh") {
      await adapter.refresh();
    }
  });

  root.addEventListener("odyssey:tabshow", () => {
    void adapter.refresh();
  });

  render();
  store.initialize();

  return () => {
    unsubscribe?.();
    store.dispose();
    adapter.dispose();
  };
}
