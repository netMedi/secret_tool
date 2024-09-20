import { $ } from "bun";
import { existsSync } from "fs";
import { NETMEDI_MONOREPO_HOME, SECRET_TOOL_DIR_SRC, SECRET_TOOL_GIT_REPO } from './defaults';

const selfUpdate = async (install = true) => {
  if (existsSync(SECRET_TOOL_DIR_SRC)) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && sh ./secret_utils.sh update ${install ? '' : '--no-install'}`;
    return;
  }

  console.log("[INFO] Unable to find the secret_tool's source directory");
  console.log("[INFO] Cloning to the default secret_tool's source repository...");
  console.log('[', SECRET_TOOL_DIR_SRC, ']');
  await $`mkdir -p ${NETMEDI_MONOREPO_HOME}/secret_tool; git clone ${SECRET_TOOL_GIT_REPO} ${NETMEDI_MONOREPO_HOME}/secret_tool`;
  selfUpdate(install);
};

export default selfUpdate;
