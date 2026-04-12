import { Command } from "commander";
import { request, setDaemonArgs } from "./client";

const program = new Command();

program
  .name("weblens")
  .version("0.1.0")
  .description("Web execution CLI for AI agents")
  .option("--headless", "Run browser without visible window")
  .argument("[url]", "URL to navigate to and read (shorthand for navigate + state)")
  .action(async (url?: string) => {
    if (!url) {
      program.help();
      return;
    }
    // Default command: navigate + return plain text snapshot
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = `https://${url}`;
    }
    if (program.opts().headless) setDaemonArgs(["--headless"]);
    await request("POST", "/navigate", { url });
    const result = await request("GET", "/state") as any;
    console.log(`# ${result.title}`);
    console.log(`# ${result.url}`);
    console.log("");
    console.log(result.snapshot);
    if (result.humanActivity) {
      console.log("");
      console.log(`[human activity: ${result.humanActivity.actions.map((a: any) => a.url).join(", ")}]`);
    }
  });

program.hook("preSubcommand", () => {
  if (program.opts().headless) setDaemonArgs(["--headless"]);
});

program
  .command("navigate <url>")
  .description("Navigate to a URL and return snapshot")
  .action(async (url: string) => {
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = `https://${url}`;
    }
    const result = await request("POST", "/navigate", { url }) as any;
    console.log(`# ${result.title}`);
    console.log(`# ${result.url}`);
    console.log("");
    console.log(result.snapshot);
    if (result.humanActivity) {
      console.log("");
      console.log(`[human activity: ${result.humanActivity.actions.map((a: any) => a.url).join(", ")}]`);
    }
  });

program
  .command("state")
  .description("Get page state as plain text (--json for JSON, --full for uncompacted)")
  .option("--full", "Include all elements")
  .option("--json", "Output as JSON instead of plain text")
  .action(async (opts: { full?: boolean; json?: boolean }) => {
    const path = opts.full ? "/state?full=1" : "/state";
    const result = await request("GET", path) as any;
    if (opts.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(result.snapshot);
    }
  });

program
  .command("do <ref>")
  .description("Interact with an element by ref ID")
  .option("--value <text>", "Value to type/select")
  .action(async (ref: string, opts: { value?: string }) => {
    const body: any = { ref };
    if (opts.value !== undefined) body.value = opts.value;
    const result = await request("POST", "/do", body);
    console.log(JSON.stringify(result, null, 2));
  });

program
  .command("diff")
  .description("Show changes since last snapshot")
  .action(async () => {
    const result = await request("GET", "/diff");
    console.log(JSON.stringify(result, null, 2));
  });

const session = program
  .command("session")
  .description("Manage browser sessions");

session
  .command("save <name>")
  .description("Save current session (cookies, storage)")
  .action(async (name: string) => {
    const result = await request("POST", "/session/save", { name });
    console.log(JSON.stringify(result, null, 2));
  });

session
  .command("load <name>")
  .description("Load a saved session")
  .action(async (name: string) => {
    const result = await request("POST", "/session/load", { name });
    console.log(JSON.stringify(result, null, 2));
  });

session
  .command("list")
  .description("List saved sessions")
  .action(async () => {
    const result = await request("GET", "/session/list");
    console.log(JSON.stringify(result, null, 2));
  });

program
  .command("stop")
  .description("Stop the background browser daemon")
  .action(async () => {
    try {
      const result = await request("POST", "/stop");
      console.log(JSON.stringify(result, null, 2));
    } catch {
      console.log(JSON.stringify({ stopped: true, note: "daemon was not running" }));
    }
  });

program
  .command("describe")
  .description("Output a prompt snippet describing weblens for LLMs")
  .action(() => {
    console.log(`weblens <url> reads a webpage. weblens do <ref> clicks an element. weblens do <ref> --value "x" types. weblens state re-reads. weblens session list/load/save manages auth.`);
  });

program.parseAsync(process.argv).catch((err) => {
  console.error(err.message);
  process.exit(1);
});
