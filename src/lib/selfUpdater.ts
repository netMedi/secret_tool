import { $ } from "bun";
import { existsSync } from "fs";
import { SECRET_TOOL_DIR_SRC, SECRET_TOOL_GIT_REPO } from './defaults';

const selfUpdate = async () => {
  if (existsSync(SECRET_TOOL_DIR_SRC)) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && bun ./secret_utils.sh update`;
    return;
  }

  console.log("[INFO] Unable to find the secret_tool's source directory");
  console.log("[INFO] Cloning to the default secret_tool's source repository...");
  console.log('[', SECRET_TOOL_DIR_SRC, ']');
  await $`git clone ${SECRET_TOOL_GIT_REPO} ${SECRET_TOOL_DIR_SRC}`;
  selfUpdate();
};

export default selfUpdate;
