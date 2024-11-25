#!/usr/bin/env bun

import { $ } from 'bun';
import { hostname, userInfo } from 'os';

declare const BUN_VERSION: string;
declare const COMPILE_TIME_DATE: string;
declare const COMPILE_TIME_DIR_SRC: string;

import { SECRET_TOOL_DIR_SRC } from './lib/defaults';
import { TOOL_VERSION } from './lib/pkgInfo';
import output from './lib/dumper';
import selfInstall from './lib/selfInstaller';
import selfTest from './lib/selfTester';
import selfUpdate from './lib/selfUpdater';

const srcRun = process.execPath.split('/').pop() === 'bun';
const secretToolPath = srcRun ? Bun.argv[1] : process.execPath;
const SECRET_TOOL = process.env.SECRET_TOOL || secretToolPath.split('/').pop();
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

const displayHelp = () => console.log(helpText.slice(1, -1));
const displayVersion = () => {
  console.log(
    '  Version number   :',
    TOOL_VERSION,
    '\n  Executable path  :',
    secretToolPath,
  );
  if (srcRun) {
    console.log(
      '  This is a source run without installation. Use `--install` to install.',
    );
  } else {
    console.log(
      '  Compilation dir  :',
      COMPILE_TIME_DIR_SRC,
      '\n  Compilation date :',
      COMPILE_TIME_DATE,
      '\n  Compiler version : Bun',
      BUN_VERSION,
    );
  }
  console.log('  Context user     :', `${userInfo().username}@${hostname()}`);
};

const main = async () => {
  const cliArguments = Bun.argv.slice(2);

  if (cliArguments.includes('--version')) {
    displayVersion();
    process.exit(0);
  }

  // redundant shortcuts to secret_utils' operations
  if (cliArguments.includes('--build')) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && sh ./secret_utils.sh build`;
    process.exit(0);
  }
  if (cliArguments.includes('--install')) {
    const noConfirm = ['-y', '--yes', '--no-confirm'].some(arg =>
      cliArguments.includes(arg),
    );
    await selfInstall(noConfirm);
    process.exit(0);
  }
  if (cliArguments.includes('--test')) {
    await selfTest(Bun.argv[1]);
    process.exit(0);
  }
  if (cliArguments.includes('--uninstall')) {
    await $`cd ${SECRET_TOOL_DIR_SRC} && sh ./secret_utils.sh uninstall`;
    process.exit(0);
  }
  if (cliArguments.includes('--update')) {
    await selfUpdate();
    process.exit(0);
  }

  if (cliArguments.includes('--help') || cliArguments.length === 0) {
    displayHelp();
    // console.log();
    // displayVersion();
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
