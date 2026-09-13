export const commandPath = "/api/v1/command";
export const eventsPath = "/api/v1/events";

export interface ServerEvent {
  id?: string;
  event: string;
  data: string;
}

export function eventsEndpoint(commandEndpoint: string): string {
  const endpoint = commandEndpoint.split("?", 1)[0] ?? commandEndpoint;
  if (!endpoint.endsWith(commandPath))
    throw new Error("Adresse Wi-Fi du réveil invalide");
  return `${endpoint.slice(0, -commandPath.length)}${eventsPath}`;
}

export function parseFrame(frame: string): ServerEvent | undefined {
  const parsed: { id?: string; event: string; dataLines: string[] } = {
    event: "message",
    dataLines: [],
  };
  for (const line of frame.split("\n")) {
    if (!line.trim() || line.startsWith(":")) continue;
    const separatorIndex = line.indexOf(":");
    const field = separatorIndex < 0 ? line : line.slice(0, separatorIndex);
    let value = separatorIndex < 0 ? "" : line.slice(separatorIndex + 1);
    if (value.startsWith(" ")) value = value.slice(1);
    if (field === "event") parsed.event = value.trim() ? value : "message";
    else if (field === "data") parsed.dataLines.push(value);
    else if (field === "id" && !value.includes("\0")) parsed.id = value;
  }
  if (parsed.dataLines.length === 0) return undefined;
  return {
    ...(parsed.id !== undefined ? { id: parsed.id } : {}),
    event: parsed.event,
    data: parsed.dataLines.join("\n"),
  };
}

export function consumeChunk(
  buffer: string,
  chunk: string,
): { buffer: string; events: ServerEvent[] } {
  const combined = `${buffer}${chunk}`;
  const trailingCarriageReturn = combined.endsWith("\r");
  const complete = trailingCarriageReturn ? combined.slice(0, -1) : combined;
  let remaining =
    complete.replaceAll("\r\n", "\n").replaceAll("\r", "\n") +
    (trailingCarriageReturn ? "\r" : "");
  const events: ServerEvent[] = [];
  let separatorIndex = remaining.indexOf("\n\n");
  while (separatorIndex >= 0) {
    const event = parseFrame(remaining.slice(0, separatorIndex));
    if (event) events.push(event);
    remaining = remaining.slice(separatorIndex + 2);
    separatorIndex = remaining.indexOf("\n\n");
  }
  return { buffer: remaining, events };
}
