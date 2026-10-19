import { readFileSync } from "node:fs";

export const read_fixture = (name) => readFileSync(`test/${name}`, "utf8");
