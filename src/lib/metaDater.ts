import fs from 'fs';

const fileModifiedDateFromFS = (fileName: string): string => {
  if (fs.existsSync(fileName)) {
    // TODO: simplify this to avoid unneeded replaces
    return fs.statSync(fileName).mtime.toISOString()
      .split('.')[0].replace('T', '_').replace(' ', '_').replaceAll(':', '-');
  } else {
    throw new Error(`File not found: ${fileName}`);
  }
}

export default fileModifiedDateFromFS;
