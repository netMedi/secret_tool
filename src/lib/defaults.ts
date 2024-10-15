import { existsSync } from 'fs';
import { homedir } from 'os';
import { dirname } from 'path';

declare const COMPILE_TIME_DIR_SRC: string;

export const NETMEDI_MONOREPO_HOME = process.env.NETMEDI_MONOREPO_HOME || `${homedir()}/netMedi/`;

export let SECRET_TOOL_DIR_SRC: string;

try {
  SECRET_TOOL_DIR_SRC = existsSync(COMPILE_TIME_DIR_SRC) ?
    COMPILE_TIME_DIR_SRC :
    process.env.SECRET_TOOL_DIR_SRC || `${NETMEDI_MONOREPO_HOME}/secret_tool/`;
}
catch (e) {
  if (e instanceof ReferenceError) {
    SECRET_TOOL_DIR_SRC = dirname(dirname(Bun.argv[1]));
  } else {
    throw e;
  }
}

export const SECRET_TOOL_GIT_REPO = 'git@github.com:netMedi/secret_tool.git';

export const SECRET_MAP = './secret_map.yml';
export const FORMAT = 'e'; // e: envfile, j: json, y: yaml
