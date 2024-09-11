import { homedir } from 'os';

export const NETMEDI_MONOREPO_HOME = process.env.NETMEDI_MONOREPO_HOME || `${homedir()}/netMedi/`;
export const SECRET_TOOL_DIR_SRC = process.env.SECRET_TOOL_DIR_SRC || `${NETMEDI_MONOREPO_HOME}/secret_tool/`;

export const SECRET_TOOL_GIT_REPO = 'git@github.com:netMedi/secret_tool.git';
