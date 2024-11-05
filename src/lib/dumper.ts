import { sync } from 'glob';
import { resolve } from 'path';
import fs from 'fs';
import yaml from 'js-yaml';

import { FORMAT, SECRET_MAP } from './defaults';
import { TOOL_VERSION } from './pkgInfo';

import dumpFileHeaders from './headerDataProvider';
import opValueOrLiteral, { getOpAuth } from './opSecretDataProvider';
import produceBackup from './backuper';

import type { EnvMap, SecretProps } from './types';
import fsDateTimeModified from './fsFileDataProvider';
import verGreaterOrEqual from './verGte';

const castStringArr = (value: string | undefined): string[] => value ? value.split(' ') : [];
const castBool = (value: string | undefined, defaultValue = false): boolean => value ? Boolean(JSON.parse(String(value))) : defaultValue;

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
      if (typeof obj[k] === 'object' && obj[k] !== null && !Array.isArray(obj[k])) {
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
    {} as { [key: string]: any }
  );

  return Object.fromEntries(Object.entries(flatObjUppercase).sort());
}

const overrideFlatObj = (
  inputObj: EnvMap,
  localOverrides: EnvMap,
  secretProps: SecretProps
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
}

// replaces surrounding double-quotes with single-quotes
// if there are no single-quotes or dollars inside
const switchQuotes = (val: string) => {
  if (!val.startsWith('"')) return val;
  return (val.includes("'") || val.includes("$"))
    ? val
    : `'${val.slice(1, -1)}'`;
};

const envFileContent = (inputObj: object) => {
  const flatObj = flattenObj(inputObj);

  let envfileString: string[] = [];
  yaml.dump(flatObj, { forceQuotes: true, quotingType: "'" })
    .split('\n').forEach((line: string) => {
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
    })

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
  fileNameBaseRaw: string,
  profileRaw: string,
  secretProps: SecretProps,
) => {
  let [profile, fileNameBase] = [profileRaw, fileNameBaseRaw];
  if (profileRaw.indexOf('/') !== -1) {
    let pathBits = profileRaw.split('/');
    profile = pathBits.pop() as string;
    fileNameBase = (
      pathBits.join('/') + '/' + (secretProps.fileNameBase || '')
    ).replaceAll('//', '/'); // cosmetics: replace // with /
  }

  const {format, liveDangerously, secretMapPaths, skipHeadersUse} = secretProps;

  const formatId = (secretProfile['--FORMAT'] || format)[0].toLowerCase();
  const skipBackups = liveDangerously;

  let extension = '';
  switch(formatId){
    case 'j':
      extension = '.json';
      break;
    case 'y':
      extension = '.yml';
      break;
  }

  let path = fileNameBase;
  if (!!!path) {
    path = './.env.';
  }
  if (path !== '--') {
    path = resolve(path + profile + extension);
  }

  const headers = skipHeadersUse
    ? undefined
    : dumpFileHeaders(
      path,
      secretMapPaths,
      profile,
      locallyOverriddenVariables,
      excludedBlankVariables
    );

  let res = (() => {
    switch (formatId) {
      case 'j':
        return jsonFileContent({ '//': headers, ...secretProfile });
      case 'y':
        return yamlFileContent({ '//': headers, ...secretProfile });
      default:
        const cleanHeaders: string[] = [];
        yaml.dump(headers, { flowLevel: 1 })
          .split('\n')
          .forEach((line: string) => cleanHeaders.push(line.slice(1).replace("': ", ': ')));
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

const output = async (
  localOverrides: EnvMap,
  cliArguments: string[]
) => {
  const secretProps = {
    secretMapPaths: process.env.SECRET_MAP || SECRET_MAP,
    format: process.env.FORMAT || FORMAT,

    excludeEmptyStrings: castBool(process.env.EXCLUDE_EMPTY_STRINGS, true),
    fileNameBase: process.env.FILE_NAME_BASE,
    filePostfix: process.env.FILE_POSTFIX,
    extract: castStringArr(process.env.EXTRACT),
    skipHeadersUse: castBool(process.env.SKIP_HEADERS_USE),
    skipOpUse: castBool(process.env.SKIP_OP_USE),

    skipOpMarker: process.env.SKIP_OP_MARKER ,
    skipOpMarkerWrite: castBool(process.env.SKIP_OP_MARKER_WRITE),

    liveDangerously: castBool(process.env.LIVE_DANGEROUSLY),
    metaData: {},
  } as SecretProps;

  const secretMap: EnvMap = {};
  const secretMapFragments = secretProps.secretMapPaths.split(' ');
  let secretMapFragmentsRead = 0;
  for (const secretMapMask of secretMapFragments) {
    // Read the files using glob
    const filePaths = sync(secretMapMask);

    for (const filePath of filePaths) {
      let fileContent: EnvMap;
      try {
        fileContent = yaml.load(fs.readFileSync(filePath, 'utf8')) as unknown as EnvMap;
        secretProps.metaData[filePath] = fsDateTimeModified(filePath);
        secretMapFragmentsRead++;
      } catch (_) {
        continue;
      }

      // Deep merge fileContent object into secretMap object
      Object.keys(fileContent).forEach(key => {
        if (secretMap[key] && typeof secretMap[key] === 'object') {
          Object.assign(secretMap[key], fileContent[key]);
        } else {
          secretMap[key] = fileContent[key];
        }
      });
    }
  }

  if (secretMapFragmentsRead === 0) {
    console.log('[ERROR] Secret map not found in', secretMapFragments);
    console.log('[INFO] You can set SECRET_MAP environment variable (space separated list of masks)');
    process.exit(1);
  }

  const smToolVersionMin = secretMap['tool_version'];
  if (smToolVersionMin !== undefined && !verGreaterOrEqual(TOOL_VERSION, smToolVersionMin)) {
    console.log('[ERROR] Secret tool installed is too old to handle this secret map.');
    console.log('[INFO] Min required secret_tool version :', smToolVersionMin);
    console.log('[INFO] Installed secret_tool version    :', TOOL_VERSION);
    console.log();
    console.log('[INFO] You can update secret_tool by running:');
    console.log(`  VERSION=v${smToolVersionMin} secret_tool --update`);
    process.exit(1);
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
    : [
      ...secretProps.extract,
      ...cliArguments
    ];

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

  profilesReq.forEach(profile => {
    if (!profilesAll.includes(profile)) {
      console.log(
        '[ERROR] Profile validation failed.',
        `Profile "${profile}" was not found in`,
        Object.keys(secretProps.metaData)
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
        console.log(`[ERROR] Extending on top of profile "${baseProfileToExtendUpon}" is not possible. It was not found`);
        process.exit(1);
      }

      profilesToExtend.unshift(flattenObj(newBase));
      baseProfileToExtendUpon = newBase['--extend'];
    }

    const profileFlatExtended = Object.assign({}, ...profilesToExtend, profileFlatDefault);

    const [profileFlatOverridden, locallyOverriddenVariables, excludedBlankVariables] = overrideFlatObj(profileFlatExtended, localOverrides, secretProps);

    formatOutput(
      profileFlatOverridden,
      locallyOverriddenVariables,
      excludedBlankVariables,
      secretProps.fileNameBase,
      profile,
      secretProps
    );
  });

  console.log('\n[INFO] Extraction completed.\n');
};

export default output;
