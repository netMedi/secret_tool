import { $ } from 'bun';
import { existsSync } from 'fs';
import { SECRET_TOOL_DIR_SRC } from './defaults';
import selfUpdate from './selfUpdater';

const selfTest = async (secretToolExe = 'secret_tool') => {
  if (existsSync(SECRET_TOOL_DIR_SRC)) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && SECRET_TOOL_EXE=$(command -v ${secretToolExe}) sh ./secret_utils.sh test`;
    return;
  }

  // if secret_utils are not found, perform self update
  selfUpdate();
  selfTest(secretToolExe);
};

export default selfTest;
