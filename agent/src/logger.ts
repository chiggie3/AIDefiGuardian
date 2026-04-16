import fs from "fs";
import path from "path";

const LOG_FILE = path.join(__dirname, "..", "agent.log");

/**
 * Extract caller's filename and function name from the call stack.
 * Stack levels: 0=getCallerInfo, 1=log, 2=info/warn/error, 3=actual caller.
 */
function getCallerInfo(): { file: string; func: string } {
  const stack = new Error().stack;
  if (!stack) return { file: "unknown", func: "unknown" };

  const lines = stack.split("\n");
  // Line 4 is the actual caller (0=Error, 1=getCallerInfo, 2=log, 3=info/warn/error, 4=caller)
  const callerLine = lines[4] || "";

  // Match "at functionName (/path/to/file.ts:line:col)"
  const matchWithFunc = callerLine.match(/at\s+(\S+)\s+\(.*\/([^/]+):\d+:\d+\)/);
  if (matchWithFunc) {
    return { file: matchWithFunc[2], func: matchWithFunc[1] };
  }

  // Match "at /path/to/file.ts:line:col" (anonymous function / top-level code)
  const matchAnon = callerLine.match(/at\s+.*\/([^/]+):\d+:\d+/);
  if (matchAnon) {
    return { file: matchAnon[1], func: "<top>" };
  }

  return { file: "unknown", func: "unknown" };
}

function log(level: string, message: string, data?: unknown): void {
  const { file, func } = getCallerInfo();
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    source: `${file}:${func}`,
    message,
    ...(data !== undefined && { data }),
  };
  const line = JSON.stringify(entry);
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + "\n");
}

export const logger = {
  info: (message: string, data?: unknown) => log("INFO", message, data),
  warn: (message: string, data?: unknown) => log("WARN", message, data),
  error: (message: string, data?: unknown) => log("ERROR", message, data),
};
