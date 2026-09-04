// Builds a prompt using the worker's own module, so the evals grade exactly
// what ships. Reads a request body as JSON on stdin, prints {system, user,
// promptVersion} as JSON on stdout.
import { systemFor, userMessage, PROMPT_VERSION } from "../proxy/src/prompts.js";

let input = "";
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
  const body = JSON.parse(input);
  process.stdout.write(JSON.stringify({
    system: systemFor(body),
    user: userMessage(body),
    promptVersion: PROMPT_VERSION,
  }));
});
