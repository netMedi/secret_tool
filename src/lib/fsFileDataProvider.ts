import fs from 'fs';

const dateFromMTime = (mtime: Date, filenameFriendly = false): string => {
  const YYYY = String(mtime.getFullYear());
  const MM = String(mtime.getMonth() + 1).padStart(2, '0');
  const DD = String(mtime.getDate()).padStart(2, '0');

  const hh = String(mtime.getHours()).padStart(2, '0');
  const mm = String(mtime.getMinutes()).padStart(2, '0');
  const ss = String(mtime.getSeconds()).padStart(2, '0');

  const datetimeString = (filenameFriendly = false) => {
    const dateString = `${YYYY}-${MM}-${DD}`;
    const timeString = `${hh}:${mm}:${ss}`;

    if (filenameFriendly) {
      return `${dateString}_${timeString}`;
    } else {
      const tzOffsetRaw = mtime.getTimezoneOffset();

      const sign = tzOffsetRaw > 0 ? '-' : '+';
      const absOffset = Math.abs(tzOffsetRaw);
      const hours = String(Math.floor(absOffset / 60)).padStart(2, '0');
      const minutes = String(absOffset % 60).padStart(2, '0');
      const tzOffset = `${sign}${hours}:${minutes}`;

      return `${dateString} at ${timeString}${tzOffset}`;
    }
  };

  return datetimeString(filenameFriendly);
};

const fsDateTimeModified = (fileName: string, filenameFriendly = false): string => {
  if (fs.existsSync(fileName)) {
    return dateFromMTime(fs.statSync(fileName).mtime, filenameFriendly);
  } else {
    throw new Error(`File not found: ${fileName}`);
  }
};

export default fsDateTimeModified;
