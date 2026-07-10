export function normalizeRpcError(error) {
  if (error && typeof error === "object" && error.ok === false) {
    return {
      ok: false,
      error: String(error.error ?? error.code ?? "RPC_EXCEPTION"),
      message: String(error.message ?? "RPC request failed."),
      rpcException: Boolean(error.rpcException),
      retryable: Boolean(error.retryable),
      details: error.details ?? null,
      stage: error.stage ?? null,
    };
  }

  const message = String(
    error?.message
    ?? error?.details
    ?? error?.error_description
    ?? error
    ?? "",
  ).trim() || "RPC request failed.";
  const lowered = message.toLowerCase();

  if (lowered.includes("canceling statement due to statement timeout")) {
    return {
      ok: false,
      error: "STATEMENT_TIMEOUT",
      message,
      rpcException: true,
      retryable: true,
      details: error?.details ?? null,
      stage: error?.stage ?? null,
    };
  }

  return {
    ok: false,
    error: String(error?.code ?? "RPC_EXCEPTION"),
    message,
    rpcException: true,
    retryable: false,
    details: error?.details ?? null,
    stage: error?.stage ?? null,
  };
}

export function toRpcException(normalizedError) {
  const normalized = normalizeRpcError(normalizedError);
  const exception = new Error(normalized.message);
  exception.ok = false;
  exception.code = normalized.error;
  exception.error = normalized.error;
  exception.message = normalized.message;
  exception.rpcException = normalized.rpcException;
  exception.retryable = normalized.retryable;
  exception.details = normalized.details;
  exception.stage = normalized.stage;
  return exception;
}
