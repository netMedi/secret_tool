import { resolve } from 'path';
import fs from 'fs';
import yaml from 'js-yaml';
import opValueOrLiteral, { getOpAuth } from './opSecretDataProvider';
import produceBackup from './backuper';
import dumpFileHeaders from './headerDataProvider';
import type { EnvMap, SecretProps } from './types';
import { FORMAT, SECRET_MAP } from './defaults';

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

  const flatObjUnsorted = flattenNestedObjects(flattenNestedArray(inputObj));
  return Object.fromEntries(Object.entries(flatObjUnsorted).sort());
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
  yaml.dump(flatObj, { forceQuotes: true, quotingType: '"' })
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

  const {format, liveDangerously, secretMapPath, skipHeadersUse} = secretProps;

  const formatId = (secretProfile['--format'] || format)[0].toLowerCase();
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
      secretMapPath,
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
    console.log(output);
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
    secretMapPath: process.env.SECRET_MAP || SECRET_MAP,
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
  } as SecretProps;

  let secretMap: EnvMap;
  // Get document, or throw exception on error
  try {
    secretMap = yaml.load(
      fs.readFileSync(secretProps.secretMapPath, 'utf8')
    ) as unknown as EnvMap;
  } catch (_) {
    console.log('[ERROR] Secret map is not available at', secretProps.secretMapPath);
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
      console.log('[ERROR] Profile validation failed: profile', profile, 'was not found in', secretProps.secretMapPath);
      process.exit(1);
    }

    console.log(`\n[INFO] Extracting values (${profile})...`);

    const profileFromMap = secretMap['profiles'][profile];
    const profileFlatDefault = flattenObj(profileFromMap);
    const [profileFlatOverridden, locallyOverriddenVariables, excludedBlankVariables] = overrideFlatObj(profileFlatDefault, localOverrides, secretProps);

    formatOutput(
      profileFlatOverridden,
      locallyOverriddenVariables,
      excludedBlankVariables,
      secretProps.fileNameBase,
      profile,
      secretProps
    );
  });
};

export default output;
