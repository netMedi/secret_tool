import { $ } from "bun";
import { SECRET_TOOL_DIR_SRC, SECRET_TOOL_GIT_REPO } from './defaults';

const update = async () => {

  try {
    const result = await $`git clone ${SECRET_TOOL_GIT_REPO} ${SECRET_TOOL_DIR_SRC}`;
    console.log("Clone successful, exit code:", result.exitCode);
  } catch (error) {
    console.error("Clone failed:", error);
  }
};

export default update;
