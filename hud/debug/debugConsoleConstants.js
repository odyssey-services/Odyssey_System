// Odyssey Debug Console — shared, PURE constants (TEMPORARY).
//
// Imported by BOTH debugConsoleController.js (background) and
// debugConsolePage.js (iframe) so neither pulls in the other's logic.
// Deliberately separate from hud/overlay/overlayConstants.js.

export const BC_DEBUG_CONSOLE_ENTRIES = "com.odyssey.debug-console/entries";
export const BC_DEBUG_CONSOLE_REQUEST = "com.odyssey.debug-console/request";
export const BC_DEBUG_CONSOLE_COMMAND = "com.odyssey.debug-console/command";
// Cross-bundle error reporting (hud/debug/debugLogClient.js): any iframe/
// bundle that cannot import debugLogStore.js directly (it runs in a
// different JS realm than background.js) sends its error here instead, and
// debugConsoleController.js is the only listener — see debugLogClient.js's
// header comment for the full reasoning.
export const BC_DEBUG_CONSOLE_LOG_EVENT = "com.odyssey.debug-console/log-event";
