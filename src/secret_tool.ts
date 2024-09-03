#!/usr/bin/env bun

import pkgInfo from "../package.json" with { type: "json" };
import output from "./lib/extractor";

const cmd_name = 'secret_tool';
const helpText = `
  Script: ${cmd_name}
  Purpose: Produce file(s) with environment variables and secrets from 1password using secret map

  Usage: [OVERRIDES] ${cmd_name} [PROFILE_NAME(S)]
  (if any dashed arguments are present, all other arguments are ignored)
    ${cmd_name} --version                        # print version info and exit
    ${cmd_name} --help                           # print help and exit
    ${cmd_name} --update                         # perform self-update and exit (only for full git install)
    ${cmd_name} --test                           # perform self-test and exit (only for full git install)
    ${cmd_name} --profiles                       # list all available profiles and exit
    ${cmd_name} --all                            # dump secrets for all profiles

  Examples:
    ${cmd_name} staging                          # dump secrets for this profile
    ${cmd_name} dev test                         # dump secrets for these two profiles
    VAR123='' ${cmd_name}                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' ${cmd_name} test  # use this map file
    EXCLUDE_EMPTY_STRINGS=1 ${cmd_name} dev      # dump all, exclude blank values
    FILE_NAME_BASE='/tmp/.env.' ${cmd_name} dev  # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX='.sh' ${cmd_name} prod          # append this to file name end (.env.prod.sh)
    EXTRACT='ci test' ${cmd_name}                # set target profiles via variable (same as \`${cmd_name} ci test\`)
    SKIP_OP_USE=1 ${cmd_name} ci                 # do not use 1password
`;

const displayHelp = () => console.log(helpText.slice(1, -1));
const displayVersion = () => console.log(pkgInfo.version);

const main = () => {
  const cliArguments = Bun.argv.slice(2);

  if (cliArguments.includes('--help')) {
    displayHelp();
    process.exit(0);
  }

  if (cliArguments.includes('--version')) {
    displayVersion();
    process.exit(0);
  }

  // TODO
  if (cliArguments.includes('--update')) {
    process.exit(0);
  }

  // TODO
  if (cliArguments.includes('--test')) {
    process.exit(0);
  }

  // console.dir(process.env);
  // process.exit(0);

  const exitCode: number | undefined = output(process.env, cliArguments);
  switch (exitCode) {
    case 0:
      break;
    case 1:
      displayHelp();
      break;
    default:
      displayVersion();
  }
};

main();
