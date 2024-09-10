import { resolve } from 'path';
import fs from 'fs';
import yaml from 'js-yaml';
import opValueOrLiteral, { getOpAuth } from './opHandler';
import produceBackup from './backuper';

type SecretProps = {
  secretMapPath: string;
  format: string;

  excludeEmptyStrings: boolean;
  fileNameBase: string;
  filePostfix: string;
  extract: string[];
  skipOpUse: boolean;

  // flag-file to skip using 1password if present
  skipOpMarker: string | undefined;
  skipOpMarkerWrite: boolean;

  // skip backup creation if true
  liveDangerously: boolean;
};
type EnvMap = { [key: string]: any };

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
) => {
  // for each key present in inputObj replace value with value from overrides if present
  for (const key of Object.keys(inputObj)) {
    if (localOverrides.hasOwnProperty(key)) inputObj[key] = localOverrides[key];

    switch (inputObj[key]) {
      case '':
        if (secretProps.excludeEmptyStrings) delete inputObj[key];
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
      default:
        if (typeof inputObj[key] === 'string') {
          inputObj[key] = opValueOrLiteral(inputObj[key], secretProps.skipOpUse);
        }
    }
  }
  return inputObj;
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

  let envfileString = '';
  yaml.dump(flatObj, { forceQuotes: true, quotingType: '"' })
    .split('\n').forEach((line: string) => {
      const separator = ': ';
      const [key, ...rest] = line.split(separator);
      const value = rest.join(separator);
      if (key !== '' && key.indexOf('--') === -1) {
        switch (value) {
          case '[]':
            envfileString = envfileString + `# ${key.toUpperCase().replaceAll('-', '_')} is an empty array\n`
            break;
          case '{}':
            envfileString = envfileString + `# ${key.toUpperCase().replaceAll('-', '_')} is an empty object\n`
            break;
          default:
            envfileString = envfileString + `${key.toUpperCase().replaceAll('-', '_')}=${switchQuotes(value)}\n`
        }
      }
    })

  return envfileString;
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
  const doubleQuotedYaml = yaml.dump(nestedObj, { quotingType: '"', indent: 2 });

  /*
  const lines = [];
  for (const line of doubleQuotedYaml.split('\n')) {
    // match line that ends with " and replace it with ' unless there are ' or $ inside
    // replace any \" with " (unescape double-quotes)
    lines.push(line.replace(/^"([^"$]*)\"([^"$]*)"$|^"([^"$]*)"$|^"([^"$]*)\"$/g, "'$1$3$4'").replace(/"/g, "'"));
  }
  return lines.join('\n');
  */

  return doubleQuotedYaml;
};

const formatOutput = (
  secretProfile: EnvMap,
  fileNameBase: string,
  profile: string,
  format: string,
  skipBackups: boolean
) => {
  const jsObject = secretProfile;

  let [extension, res] = ['', ''];
  switch(format){
    case 'j':
      extension = '.json';
      res = jsonFileContent(jsObject);
      break;
    case 'y':
      extension = '.yml';
      res = yamlFileContent(jsObject);
      break;
    default:
      res = envFileContent(jsObject);
  }

  let path = fileNameBase;
  if (!!!path) {
    path = './.env.';
  }
  else if (path === '--') {
    console.log(output);
    return;
  }

  path = resolve(path + profile + extension);

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
    secretMapPath: process.env.SECRET_MAP || './secret_map.yml',
    format: process.env.FORMAT || 'e',

    excludeEmptyStrings: castBool(process.env.EXCLUDE_EMPTY_STRINGS, true),
    fileNameBase: process.env.FILE_NAME_BASE,
    filePostfix: process.env.FILE_POSTFIX,
    extract: castStringArr(process.env.EXTRACT),
    skipOpUse: castBool(process.env.SKIP_OP_USE),

    skipOpMarker: process.env.SKIP_OP_MARKER ,
    skipOpMarkerWrite: castBool(process.env.SKIP_OP_MARKER_WRITE),

    liveDangerously: castBool(process.env.LIVE_DANGEROUSLY),
  } as SecretProps;

  if (secretProps.skipOpMarker && fs.existsSync(secretProps.skipOpMarker)) {
    secretProps.skipOpUse = true;
  }
  if (!secretProps.skipOpUse) {
    await getOpAuth();
  } else {
    if (secretProps.skipOpMarker && secretProps.skipOpMarkerWrite) {
      fs.writeFileSync(secretProps.skipOpMarker, '', { encoding: 'utf8' });
    }
  }

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

  profilesReq.forEach(profile => {
    if (!profilesAll.includes(profile)) {
      console.log('[ERROR] Profile validation failed: profile', profile, 'was not found in', secretProps.secretMapPath);
      process.exit(1);
    }

    console.log(`\n[INFO] Extracting values (${profile})...`);

    const profileFromMap = secretMap['profiles'][profile];
    const profileFlatDefault = flattenObj(profileFromMap);
    const profileFlatOverridden = overrideFlatObj(profileFlatDefault, localOverrides, secretProps);

    formatOutput(
      profileFlatOverridden,
      secretProps.fileNameBase,
      profile,
      secretProps.format[0].toLowerCase(),
      secretProps.liveDangerously
    );
  });
};

export default output;
