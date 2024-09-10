import fsDateTimeModified from "./fsFileDataProvider";

const gitDateTimeModified = (filePath: string): string => {
  const proc = Bun.spawnSync(
    ['git', 'log', '-1', '--pretty="%cI"', '--', filePath],
    { stdout: 'pipe' }
  );
  const output = proc.stdout.toString().trim();

  console.log(`'${output}'`)
  if (output === '') {
    // console.log('[DEBUG] Failed to get git date, falling back to fs');
    return fsDateTimeModified(filePath);
  }
  return output;
};

export default gitDateTimeModified;
