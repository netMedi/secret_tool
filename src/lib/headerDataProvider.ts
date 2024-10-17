import { resolve } from 'path';
import { dateFromMTime } from './fsFileDataProvider';
import { version } from '../secret_tool';
// import gitDateTimeModified from './gitFileDataProvider';
import type { EnvMap } from './types';

const dumpFileHeaders = (
  filePath: string,
  mapPath: string,
  profileName: string,
  locallyOverriddenVariables: string[],
  excludedBlankVariables: string[]
) => {
  const headers: EnvMap = {
    '# Content type': 'enviroment variables and secrets',
    '# File path': resolve(filePath),
    '# Map path': resolve(mapPath),
    '# Profile': profileName,
    '# Date of generatation': dateFromMTime(new Date()),
    '# Secret tool version': version,
    // '# Secret map release': gitDateTimeModified(mapPath),
    '# Locally overridden variables': locallyOverriddenVariables,
    '# Excluded (blank) string variables': excludedBlankVariables,
  };

  return headers;
};

export default dumpFileHeaders;
