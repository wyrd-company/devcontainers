// ---
// relationships:
//   implements: codex-cli
// ---
const { parse } = require("shell-quote");
try {
  // Variables remain literal. Parsing must never execute substitutions or expand globs.
  const args = parse(process.argv[2], (name) => "$" + name);
  if (args.some((arg) => typeof arg !== "string" || arg.includes("\0"))) {
    throw new Error(
      "Flags must contain arguments, without shell operators or glob expansion.",
    );
  }
  for (const arg of args) process.stdout.write(arg + "\0");
} catch (error) {
  console.error(
    "Invalid execServer arguments: expected CLI arguments without shell operators or glob expansion.",
  );
  process.exitCode = 1;
}
