import { existsSync } from 'fs';
import { homedir } from 'os';
import { dirname } from 'path';

declare const COMPILE_TIME_DIR_SRC: string;

export const NETMEDI_MONOREPO_HOME =
  process.env.NETMEDI_MONOREPO_HOME || `${homedir()}/netMedi/`;

export let SECRET_TOOL_DIR_SRC: string;

try {
  SECRET_TOOL_DIR_SRC = existsSync(COMPILE_TIME_DIR_SRC)
    ? COMPILE_TIME_DIR_SRC
    : process.env.SECRET_TOOL_DIR_SRC ||
      `${NETMEDI_MONOREPO_HOME}/secret_tool/`;
} catch (e) {
  if (e instanceof ReferenceError) {
    SECRET_TOOL_DIR_SRC = dirname(dirname(Bun.argv[1]));
  } else {
    throw e;
  }
}

export const SECRET_TOOL_GIT_REPO = 'git@github.com:netMedi/secret_tool.git';

export const DEFAULT_FORMAT = 'e'; // e: envfile, j: json, y: yaml

export const DEFAULT_DEBUG = '0'; // 1: true, 0: false
export const DEFAULT_EXCLUDE_EMPTY_STRINGS = '1'; // 1: true, 0: false
export const DEFAULT_LIVE_DANGEROUSLY = '0'; // 1: true, 0: false
export const DEFAULT_SECRET_MAP = './secret_map.yml ./secret_map.yml.d/*.yml';
export const DEFAULT_SKIP_HEADERS_USE = '0'; // 1: true, 0: false
export const DEFAULT_SKIP_OP_MARKER = ''; // define to check file presence for skipping OP
export const DEFAULT_SKIP_OP_MARKER_WRITE = '0'; // 1: true, 0: false
export const DEFAULT_SKIP_OP_USE = '0'; // 1: true, 0: false
