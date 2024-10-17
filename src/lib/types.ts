export type EnvMap = { [key: string]: any };

export type SecretProps = {
  secretMapPaths: string;
  format: string;

  excludeEmptyStrings: boolean;
  fileNameBase: string;
  filePostfix: string;
  extract: string[];
  skipHeadersUse: boolean;
  skipOpUse: boolean;

  // flag-file to skip using 1password if present
  skipOpMarker: string | undefined;
  skipOpMarkerWrite: boolean;

  // skip backup creation if true
  liveDangerously: boolean;
  metaData: { [key: string]: string };
};
