#!/usr/bin/env bun

import pkgInfo from "../package.json" with { type: "json" };
import fs from 'fs';
import yaml from 'js-yaml';

export const versionInfo = () => {
  console.log(`Secret Tool v${pkgInfo.version}`);
};

const flattenObj = (inputObj: object) => {

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

  return flattenNestedObjects(flattenNestedArray(inputObj));
}

const envFileContent = (inputObj: object) => {
  const flatObj = flattenObj(inputObj);

  let envfileString = '';
  yaml.dump(flatObj, { forceQuotes: true, quotingType: '"' })
    .split('\n').forEach((line: string) => {
      const separator = ': ';
      const [key, ...rest] = line.split(separator);
      const value = rest.join(separator);
      if (key !== '' && key.indexOf('--') === -1) {
        envfileString = envfileString + `${key.toUpperCase().replaceAll('-', '_')}=${value}\n`
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

    const areAllKeysIntegers = (obj: object) => Object.keys(obj).every(key => /^\d+$/.test(key));
    const isEmptyObject = (obj: object) => Object.keys(obj).length === 0 && obj.constructor === Object;

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
  return JSON.stringify(nestedObj, null, 2);
};
const yamlFileContent = (inputObj: object) => {
  const nestedObj = nestifyObj(inputObj);
  return yaml.dump(nestedObj, { quotingType: '"', indent: 2 });
};

const output = (js_object: object, output_format = 'e', output_path: string = '') => {
  let path = output_path;
  let format = output_format[0].toLowerCase();

  let [extension, output] = ['', ''];
  switch(format){
    case 'j':
      extension = '.json';
      output = jsonFileContent(js_object);
      break;
    case 'y':
      extension = '.yaml';
      output = yamlFileContent(js_object);
      break;
    default:
      output = envFileContent(js_object);
  }
  if (path === '') {
    path = './.env';
  }
  else if (path === '--') {
    console.log(output);
    return;
  }

  path = path + extension;

  console.log('Output path:', path);
  try {
    fs.writeFileSync(path, output, { encoding: 'utf8' });
  } catch (e) {
    console.error(e);
  }
};

const main = () => {

  // Get document, or throw exception on error
  const secret_map_path = process.env.SECRET_MAP || './secret_map.yml';
  const output_format = process.env.FORMAT;
  const output_path = process.env.OUTPUT_PATH;

  try {
    const doc = yaml.load(fs.readFileSync(secret_map_path, 'utf8')) as { [key: string]: any };

    output(doc, output_format, output_path);
  } catch (_) {
    console.log('[ERROR] Secret map is not available at', secret_map_path);
    process.exit(1);
  }
};

main();
