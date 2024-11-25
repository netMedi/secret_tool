import { semver } from 'bun';

const verGreaterOrEqual = (
  verThatCanBeBigger: string,
  verThatCanBeSmaller: string,
): boolean => semver.satisfies(verThatCanBeBigger, `>=${verThatCanBeSmaller}`);

export default verGreaterOrEqual;
