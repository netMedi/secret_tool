#!/usr/bin/env bun

declare const COMPILE_TIME_DATE: string;
declare const COMPILE_TIME_DIR_SRC: string;

import pkgInfo from "../package.json" with { type: "json" };
import output from "./lib/dumper";
import selfInstall from "./lib/selfInstaller";
import selfTest from "./lib/selfTester";
import selfUpdate from "./lib/selfUpdater";

const secret_tool_path = process.execPath.split('/').pop() === "bun" ? Bun.argv[1] : process.execPath;
const SECRET_TOOL = process.env.SECRET_TOOL || secret_tool_path.split('/').pop();
const helpText = `
  Script: ${SECRET_TOOL}
  Purpose: Produce file(s) with environment variables and secrets from 1password using secret map

  Usage: [OVERRIDES] ${SECRET_TOOL} [PROFILE_NAME(S)]
  (if any dashed arguments are present, all other arguments are ignored)
    ${SECRET_TOOL} --version                        # print version info and exit
    ${SECRET_TOOL} --help                           # print help and exit
    ${SECRET_TOOL} --update                         # perform self-update and exit
    ${SECRET_TOOL} --test                           # perform self-test and exit
    ${SECRET_TOOL} --profiles                       # list all available profiles and exit
    ${SECRET_TOOL} --all                            # dump secrets for all profiles

  Examples:
    ${SECRET_TOOL} staging                          # dump secrets for this profile
    ${SECRET_TOOL} dev test                         # dump secrets for these two profiles
    VAR123='' ${SECRET_TOOL}                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' ${SECRET_TOOL} test  # use this map file
    EXCLUDE_EMPTY_STRINGS=1 ${SECRET_TOOL} dev      # dump all, exclude blank values
    FILE_NAME_BASE='/tmp/.env.' ${SECRET_TOOL} dev  # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX='.sh' ${SECRET_TOOL} prod          # append this to file name end (.env.prod.sh)
    EXTRACT='ci test' ${SECRET_TOOL}                # set target profiles via variable (same as \`${SECRET_TOOL} ci test\`)
    SKIP_OP_USE=1 ${SECRET_TOOL} ci                 # do not use 1password
`;

export const version = pkgInfo.version;

const displayHelp = () => console.log(helpText.slice(1, -1));
const displayVersion = () => console.log(
  '\n  Version number:', version,
  '\n  Executable path:', secret_tool_path,
  '\n  Compiled from', COMPILE_TIME_DIR_SRC,
  '\n  Compiled on', COMPILE_TIME_DATE
);

const main = async () => {
  const cliArguments = Bun.argv.slice(2);

  if (cliArguments.includes('--version')) {
    displayVersion();
    process.exit(0);
  }

  if (cliArguments.includes('--update')) {
    await selfUpdate();
    process.exit(0);
  }

  if (cliArguments.includes('--install')) {
    await selfInstall();
    process.exit(0);
  }

  if (cliArguments.includes('--test')) {
    await selfTest(Bun.argv[1]);
    process.exit(0);
  }

  if (cliArguments.includes('--help') || cliArguments.length === 0) {
    displayHelp();
    console.log();
    displayVersion();
    process.exit(0);
  }

  const exitCode: number | undefined = await output(process.env, cliArguments);
  switch (exitCode) {
    case 0:
      break;
    case 1:
      displayHelp();
      break;
    default:
      // displayVersion();
      // TODO: dump log and/or refer to exitCode in documentation
  }
};

main();
