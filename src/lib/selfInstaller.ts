import { $ } from 'bun';
import { existsSync } from 'fs';
import { SECRET_TOOL_DIR_SRC } from './defaults';
import selfUpdate from './selfUpdater';

const selfInstall = async (noConfirm = false) => {
  if (existsSync(SECRET_TOOL_DIR_SRC)) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && sh ./secret_utils.sh install ${noConfirm ? '-y' : ''}`;
    return;
  }

  selfUpdate();
  selfInstall(noConfirm);
};

export default selfInstall;
