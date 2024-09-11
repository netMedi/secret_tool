import fsDateTimeModified from "./fsFileDataProvider";

const gitDateTimeModified = (filePath: string): string => {
  const procGitDate = Bun.spawnSync(
    ['git', 'log', '-1', '--pretty=%cI', '--', filePath],
    { stdout: 'pipe' }
  );
  const gitDate = procGitDate.stdout.toString().trim();

  if (gitDate === '') {
    // console.log('[DEBUG] Failed to get git date, falling back to fs');
    return fsDateTimeModified(filePath);
  }

  const procGitCommit = Bun.spawnSync(
    ['git', 'log', '-1', '--pretty=commit %H', '--', filePath],
    { stdout: 'pipe' }
  );
  const gitCommit = procGitCommit.stdout.toString().trim();
  return gitDate + ' ' + gitCommit;
};

export default gitDateTimeModified;
