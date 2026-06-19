export function toErrorMessage(error, fallback = "Unknown error.") {
  if (error instanceof Error && error.message.trim()) {
    return error.message.trim();
  }
  if (typeof error === "string" && error.trim()) {
    return error.trim();
  }
  if (error && typeof error === "object") {
    const message = String(
      error.message ??
        error.error_description ??
        error.error ??
        error.details ??
        "",
    ).trim();
    if (message) return message;
  }
  return fallback;
}

export function normalizeError(error, fallback = "Unknown error.") {
  return {
    name: error instanceof Error ? error.name : "Error",
    message: toErrorMessage(error, fallback),
  };
}
