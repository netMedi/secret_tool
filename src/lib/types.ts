export type EnvMap = { [key: string]: any };

export type SecretProps = {
  secretMapPaths: string;

  excludeEmptyStrings: boolean;
  extract: string[];
  skipHeadersUse: boolean;
  skipOpUse: boolean;

  // flag-file to skip using 1password if present
  skipOpMarker: string | undefined;
  skipOpMarkerWrite: boolean;

  // skip backup creation if true
  liveDangerously: boolean;
  metaData: { [key: string]: string };

  debug: boolean;
};
