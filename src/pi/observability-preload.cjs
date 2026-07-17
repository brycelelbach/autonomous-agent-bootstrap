const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const util = require("node:util");

const logDir = process.env.PI_DEBUG_LOG_DIR || path.join(os.homedir(), ".pi", "agent", "debug");
fs.mkdirSync(logDir, { recursive: true });

const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const logFile = path.join(logDir, `pi-${stamp}-${process.pid}.jsonl`);
process.env.PI_DEBUG_LOG_FILE = process.env.PI_DEBUG_LOG_FILE || logFile;
fs.closeSync(fs.openSync(logFile, "a", 0o600));
fs.chmodSync(logFile, 0o600);

function serialize(value) {
    if (value instanceof Error) {
        return {
            name: value.name,
            message: value.message,
            stack: value.stack,
        };
    }
    if (typeof value === "string") return value;
    return util.inspect(value, {
        colors: false,
        depth: 8,
        maxArrayLength: 200,
        maxStringLength: 20000,
    });
}

function record(level, args) {
    try {
        fs.appendFileSync(logFile, `${JSON.stringify({
            ts: new Date().toISOString(),
            level,
            args: Array.from(args, serialize),
        })}\n`);
    }
    catch {
        // Logging must never break Pi startup.
    }
}

for (const level of ["debug", "info", "warn", "error", "dir"]) {
    const original = console[level].bind(console);
    console[level] = (...args) => {
        record(level, args);
        if (level === "debug" || level === "info" || level === "dir") {
            if (process.env.PI_DEBUG_TEE_CONSOLE === "1") original(...args);
            return;
        }
        original(...args);
    };
}
