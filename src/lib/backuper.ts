import fs from 'fs';
import fileModifiedDateFromFS from './metaDater';

const produceBackup = (fileName: string, liveDangerously: boolean): number => {
  if (fs.existsSync(fileName) && !liveDangerously) {
    const backupFileName = `${fileName}.${fileModifiedDateFromFS(fileName)}.bak`;
    fs.copyFileSync(fileName, backupFileName);
    console.log(`[INFO] Backup created: ${backupFileName}`);
    return 0;
  }

  return 0;
};

export default produceBackup;
