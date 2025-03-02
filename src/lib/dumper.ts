import { sync } from 'glob';
import { resolve } from 'path';
import fs from 'fs';
import yaml from 'js-yaml';

import {
  DEFAULT_DEBUG,
  DEFAULT_EXCLUDE_EMPTY_STRINGS,
  DEFAULT_FORMAT,
  DEFAULT_LIVE_DANGEROUSLY,
  DEFAULT_SECRET_MAP,
  DEFAULT_SKIP_HEADERS_USE,
  DEFAULT_SKIP_OP_MARKER_WRITE,
  DEFAULT_SKIP_OP_MARKER,
  DEFAULT_SKIP_OP_USE,
} from './defaults';
import { TOOL_VERSION } from './pkgInfo';

import dumpFileHeaders from './headerDataProvider';
import opValueOrLiteral, { getOpAuth } from './opSecretDataProvider';
import produceBackup from './backuper';

import type { EnvMap, SecretProps } from './types';
import fsDateTimeModified from './fsFileDataProvider';
import verGreaterOrEqual from './verGte';

const castStringArr = (value: string | undefined): string[] =>
  value ? value.split(' ') : [];
const castBool = (value: string | undefined, defaultValue = '0'): boolean =>
  Boolean(JSON.parse(String(value || defaultValue)));

const flattenObj = (inputObj: EnvMap) => {
  // flatten nested arrays by adding index to key using double underscore as delimiter
  const flattenNestedArray = (obj: { [key: string]: any }, prefix = '') =>
    Object.keys(obj).reduce((acc: { [key: string]: any }, k) => {
      const pre = prefix.length ? prefix + '__' : '';
      if (Array.isArray(obj[k])) {
        if (obj[k].length === 0) {
          acc[pre + k] = []; // Include empty arrays
        } else {
          obj[k].forEach((v, i) => {
            acc[pre + k + '__' + i] = v;
          });
        }
      } else if (typeof obj[k] === 'object' && obj[k] !== null) {
        if (Object.keys(obj[k]).length === 0) {
          acc[pre + k] = {}; // Include empty objects
        } else {
          Object.assign(acc, flattenNestedArray(obj[k], pre + k));
        }
      } else {
        acc[pre + k] = obj[k];
      }
      return acc;
    }, {});

  // flatten nested objects using double underscore as delimiter
  const flattenNestedObjects = (obj: { [key: string]: any }, prefix = '') =>
    Object.keys(obj).reduce((acc: { [key: string]: any }, k) => {
      const pre = prefix.length ? prefix + '__' : '';
      if (
        typeof obj[k] === 'object' &&
        obj[k] !== null &&
        !Array.isArray(obj[k])
      ) {
        if (Object.keys(obj[k]).length === 0) {
          acc[pre + k] = {}; // Include empty objects
        } else {
          Object.assign(acc, flattenNestedObjects(obj[k], pre + k));
        }
      } else {
        acc[pre + k] = obj[k];
      }
      return acc;
    }, {});

  const flatObj = flattenNestedObjects(flattenNestedArray(inputObj));

  // make flatObj keys uppercase
  const flatObjUppercase = Object.keys(flatObj).reduce(
    (acc: { [key: string]: any }, key) => {
      acc[key.toUpperCase()] = flatObj[key];
      return acc;
    },
    {} as { [key: string]: any },
  );

  return Object.fromEntries(Object.entries(flatObjUppercase).sort());
};

const overrideFlatObj = (
  inputObj: EnvMap,
  localOverrides: EnvMap,
  secretProps: SecretProps,
): [EnvMap, string[], string[]] => {
  // for each key present in inputObj replace value with value from overrides if present
  const excludedBlankVariables: string[] = [];
  const locallyOverriddenVariables: string[] = [];
  for (const key of Object.keys(inputObj)) {
    if (localOverrides.hasOwnProperty(key)) {
      inputObj[key] = localOverrides[key];
      locallyOverriddenVariables.push(key);
    }

    if (typeof inputObj[key] === 'string') {
      inputObj[key] = opValueOrLiteral(inputObj[key], secretProps.skipOpUse);
    }

    switch (inputObj[key]) {
      case '':
        if (secretProps.excludeEmptyStrings) {
          delete inputObj[key];
          excludedBlankVariables.push(key.toUpperCase());
        }
        break;
      case '!![]': // this is explicit empty array
        inputObj[key] = [];
        break;
      case '!!{}': // this is explicit empty object
        inputObj[key] = {};
        break;
      case '!!': // this is explicit empty string
        inputObj[key] = '';
        break;
    }
  }
  return [inputObj, locallyOverriddenVariables, excludedBlankVariables];
};

// replaces surrounding double-quotes with single-quotes
// if there are no single-quotes or dollars inside
const switchQuotes = (val: string) => {
  if (!val.startsWith('"')) return val;
  return val.includes("'") || val.includes('$') ? val : `'${val.slice(1, -1)}'`;
};

const envFileContent = (inputObj: object) => {
  const flatObj = flattenObj(inputObj);

  let envfileString: string[] = [];
  yaml
    .dump(flatObj, { forceQuotes: true, quotingType: "'" })
    .split('\n')
    .forEach((line: string) => {
      const separator = ': ';
      const [key, ...rest] = line.split(separator);
      const value = rest.join(separator);
      if (key !== '' && key.indexOf('--') === -1) {
        const keyName = key.toUpperCase().replaceAll('-', '_');
        switch (value) {
          case '[]':
            envfileString.push(`# ${keyName} is an empty array`);
            break;
          case '{}':
            envfileString.push(`# ${keyName} is an empty object`);
            break;
          default:
            envfileString.push(`${keyName}=${switchQuotes(value)}`);
        }
      }
    });

  return envfileString.sort().join('\n') + '\n';
};

const nestifyObj = (inputObj: object) => {
  // convert flat object to nested object
  const nestify = (obj: { [key: string]: any }) => {
    const result: { [key: string]: any } = {};
    for (const key in obj) {
      const keys = key.toLowerCase().split('__'); // convert key to lowercase
      keys.reduce((acc: { [key: string]: any }, k, i) => {
        if (i === keys.length - 1) {
          acc[k] = obj[key];
        } else {
          acc[k] = acc[k] || {};
        }
        return acc[k];
      }, result);
    }
    return result;
  };

  const nestedEnvObj = nestify(inputObj);

  const areAllKeysIntegers = (obj: object) =>
    Object.keys(obj).every(key => /^\d+$/.test(key));
  const isEmptyObject = (obj: object) =>
    Object.keys(obj).length === 0 && obj.constructor === Object;

  const normaliseJSON = (obj: { [key: string]: any }) => {
    const result: { [key: string]: any } = {};
    for (const key in obj) {
      if (key.startsWith('--')) continue;
      if (obj.hasOwnProperty(key)) {
        const value = obj[key];
        if (Array.isArray(value)) {
          result[key] = value;
        } else if (typeof value === 'object' && value !== null) {
          result[key] = normaliseJSON(value);
        } else {
          result[key] = value;
        }
      }
    }
    return !isEmptyObject(result) && areAllKeysIntegers(result)
      ? Object.values(result)
      : result;
  };

  return normaliseJSON(nestedEnvObj);
};

const jsonFileContent = (inputObj: object) => {
  const nestedObj = nestifyObj(inputObj);
  return JSON.stringify(nestedObj, null, 2) + '\n';
};
const yamlFileContent = (inputObj: object) => {
  const nestedObj = nestifyObj(inputObj);
  return yaml.dump(nestedObj, { quotingType: '"', indent: 2 });
};

const formatOutput = (
  secretProfile: EnvMap,
  locallyOverriddenVariables: string[],
  excludedBlankVariables: string[],
  profile: string,
  secretProps: SecretProps,
) => {
  let pathBits: string[];

  if (profile.indexOf('/') !== -1) {
    pathBits = profile.split('/');
    profile = pathBits.pop() as string;
  } else {
    pathBits = [];
  }

  let outputPrefix = secretProfile['--PREFIX'];
  pathBits.push(outputPrefix);
  outputPrefix = pathBits.join('/').replaceAll('//', '/'); // cosmetics: replace // with /

  const outputPostfix = secretProfile['--POSTFIX'] || '';

  const { liveDangerously, secretMapPaths, skipHeadersUse } = secretProps;

  const formatId = (secretProfile['--FORMAT'] ||
    DEFAULT_FORMAT)[0].toLowerCase();
  const skipBackups = liveDangerously;

  const profileName = secretProfile['--NAME'] || profile;
  let path: string;

  let extension = '';
  switch (formatId) {
    case 'j':
      extension = '.json';
      break;
    case 'y':
      extension = '.yml';
      break;
    // default: // 'e' - no extension (envfile)
  }

  path = outputPrefix || '';
  // if (!!!path) {
  //   path = './.env.';
  // }
  if (path !== '--') {
    path = resolve(path + profileName + outputPostfix + extension);
  }

  const headers = skipHeadersUse
    ? undefined
    : dumpFileHeaders(
        path,
        secretMapPaths,
        profileName,
        locallyOverriddenVariables,
        excludedBlankVariables,
      );

  let res = (() => {
    switch (formatId) {
      case 'j':
        return jsonFileContent({ '//': headers, ...secretProfile });
      case 'y':
        return yamlFileContent({ '//': headers, ...secretProfile });
      default: // 'e'
        const cleanHeaders: string[] = [];
        yaml
          .dump(headers, { flowLevel: 1 })
          .split('\n')
          .forEach((line: string) =>
            cleanHeaders.push(line.slice(1).replace("': ", ': ')),
          );
        return cleanHeaders.join('\n') + '\n' + envFileContent(secretProfile);
    }
  })();

  if (path === '--') {
    console.log(res);
    return;
  }

  console.log('[INFO] Output:', path);
  try {
    produceBackup(path, skipBackups);
    fs.writeFileSync(path, res, { encoding: 'utf8' });
  } catch (e) {
    console.error(e);
  }
};

const output = async (localOverrides: EnvMap, cliArguments: string[]) => {
  // workaround to get shell overrides correctly and avoid reuse of cached values
  const envVars = JSON.stringify(process.env);
  const {
    SECRET_MAP,
    EXCLUDE_EMPTY_STRINGS,
    EXTRACT,
    SKIP_HEADERS_USE,
    SKIP_OP_USE,
    SKIP_OP_MARKER,
    SKIP_OP_MARKER_WRITE,
    LIVE_DANGEROUSLY,
    DEBUG,
    ..._ // discard the rest
  } = JSON.parse(envVars);

  const secretProps = {
    secretMapPaths: SECRET_MAP || DEFAULT_SECRET_MAP,

    excludeEmptyStrings: castBool(
      EXCLUDE_EMPTY_STRINGS,
      DEFAULT_EXCLUDE_EMPTY_STRINGS,
    ),

    extract: castStringArr(EXTRACT),
    skipHeadersUse: castBool(SKIP_HEADERS_USE, DEFAULT_SKIP_HEADERS_USE),
    skipOpUse: castBool(SKIP_OP_USE, DEFAULT_SKIP_OP_USE),

    skipOpMarker: SKIP_OP_MARKER || DEFAULT_SKIP_OP_MARKER,
    skipOpMarkerWrite: castBool(
      SKIP_OP_MARKER_WRITE || DEFAULT_SKIP_OP_MARKER_WRITE,
    ),

    liveDangerously: castBool(LIVE_DANGEROUSLY || DEFAULT_LIVE_DANGEROUSLY),

    debug: castBool(DEBUG || DEFAULT_DEBUG),

    metaData: {},
  } as SecretProps;

  const secretMap: EnvMap = {
    tool_version: TOOL_VERSION,
    profiles: {},
  };
  const secretMapFragments = secretProps.secretMapPaths.split(' ');
  let secretMapFragmentsRead = 0;

  const filePaths: string[] = [];
  for (const secretMapMask of secretMapFragments) {
    // Read the files using glob
    filePaths.push(...sync(secretMapMask));
  }

  if (secretProps.debug) {
    console.debug('Secret map fragments:', filePaths);
  }

  for (const filePath of filePaths) {
    if (secretProps.debug) {
      console.debug('Processing secret map fragment:', filePath);
    }

    let fileContent: EnvMap;
    try {
      fileContent = yaml.load(
        fs.readFileSync(filePath, 'utf8'),
      ) as unknown as EnvMap;

      if (secretProps.debug) {
        console.debug('File content:', fileContent);
      }

      secretProps.metaData[filePath] = fsDateTimeModified(filePath);
      secretMapFragmentsRead++;
    } catch (e) {
      if (secretProps.debug) {
        console.debug('Error reading file:', e);
      }
      continue;
    }

    // Deep merge fileContent object into secretMap object
    Object.keys(fileContent['profiles']).forEach(key => {
      if (secretProps.debug) {
        console.debug('Processing profile:', key);
      }

      if (
        secretMap['profiles'][key] &&
        typeof secretMap['profiles'][key] === 'object'
      ) {
        Object.assign(secretMap['profiles'][key], fileContent['profiles'][key]);
      } else {
        secretMap['profiles'][key] = fileContent['profiles'][key];
      }
    });
  }

  if (secretMapFragmentsRead === 0) {
    console.log('[ERROR] Secret map not found in', secretMapFragments);
    console.log(
      '[INFO] You can set SECRET_MAP environment variable (space separated list of masks)',
    );
    process.exit(1);
  }

  const smToolVersionMin = secretMap['tool_version'];
  if (
    smToolVersionMin !== undefined &&
    !verGreaterOrEqual(TOOL_VERSION, smToolVersionMin)
  ) {
    console.log(
      '[ERROR] Secret tool installed is too old to handle this secret map.',
    );
    console.log('[INFO] Min required secret_tool version :', smToolVersionMin);
    console.log('[INFO] Installed secret_tool version    :', TOOL_VERSION);
    console.log();
    console.log('[INFO] You can update secret_tool by running:');
    console.log(`  VERSION=v${smToolVersionMin} secret_tool --update`);
    process.exit(1);
  }

  if (secretProps.debug) {
    console.debug('Secret map:', secretMap);
  }

  if (secretMap['profiles'] === undefined) {
    console.log('[ERROR] Secret profiles are not available');
    process.exit(1);
  }

  const profilesAll = Object.keys(secretMap['profiles'])
    .filter(profile => !profile.startsWith('--'))
    .sort();

  if (cliArguments.includes('--profiles')) {
    console.log(profilesAll.join('\n'));
    process.exit(0);
  }

  const profilesReq = cliArguments.includes('--all')
    ? profilesAll
    : [...secretProps.extract, ...cliArguments];
  secretProps.extract = profilesReq;

  if (profilesReq.length === 0) {
    return 1;
  }

  if (secretProps.skipOpMarker && fs.existsSync(secretProps.skipOpMarker)) {
    secretProps.skipOpUse = true;
  }
  if (!secretProps.skipOpUse) {
    const opProps = await getOpAuth();
    if (opProps === null) {
      secretProps.skipOpUse = true;
    }
  } else {
    if (secretProps.skipOpMarker && secretProps.skipOpMarkerWrite) {
      fs.writeFileSync(secretProps.skipOpMarker, '', { encoding: 'utf8' });
    }
  }

  if (secretProps.debug) {
    console.debug('Available profiles:', profilesAll);
    console.debug(secretProps);
  }

  profilesReq.forEach(profile => {
    if (!profilesAll.includes(profile)) {
      console.log(
        '[ERROR] Profile validation failed.',
        `Profile "${profile}" was not found in`,
        Object.keys(secretProps.metaData),
      );
      process.exit(1);
    }

    console.log(`\n[INFO] Extracting profile: ${profile} ...`);

    const profileFromMap = secretMap['profiles'][profile];
    const profileFlatDefault = flattenObj(profileFromMap);

    const profilesToExtend: EnvMap[] = [];

    let baseProfileToExtendUpon = profileFromMap['--extend'];
    while (baseProfileToExtendUpon !== undefined) {
      const newBase = secretMap['profiles'][baseProfileToExtendUpon];
      if (newBase === undefined) {
        console.log(
          `[ERROR] Extending on top of profile "${baseProfileToExtendUpon}" is not possible. It was not found`,
        );
        process.exit(1);
      }

      profilesToExtend.unshift(flattenObj(newBase));
      baseProfileToExtendUpon = newBase['--extend'];
    }

    const profileFlatExtended = Object.assign(
      {},
      ...profilesToExtend,
      profileFlatDefault,
    );

    const [
      profileFlatOverridden,
      locallyOverriddenVariables,
      excludedBlankVariables,
    ] = overrideFlatObj(profileFlatExtended, localOverrides, secretProps);

    formatOutput(
      profileFlatOverridden,
      locallyOverriddenVariables,
      excludedBlankVariables,
      profile,
      secretProps,
    );
  });

  console.log('\n[INFO] Extraction completed.\n');
};

export default output;
