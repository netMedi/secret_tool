import { read, whoami, type ListAccount, validateCli } from "@1password/op-js";
import { version } from "../secret_tool";
import verGreaterOrEqual from "./verGte";

export const getOpAuth = async (verbose = false): Promise<ListAccount | null> => {
  const sessionData = async () => {
    console.log('[INFO] Trying to log in to 1password...');
    const proc = Bun.spawn(['op', 'signin'], {
      stdin: "inherit", // Inherit stdin from the parent process
      stdout: "pipe",   // Capture the output
    });

    // Wait for the process to exit and capture the output
    const output = await new Response(proc.stdout).text();
    const envVariableExport = output.split('#')[0].trim();

    const matchResult = envVariableExport.match(/export (\w+)="(.+?)"/);
    const [_, variableName = undefined, variableValue = undefined] = matchResult || [undefined, undefined];
    return [variableName, variableValue];
  };

  let opProps: ListAccount | null = null;
  try {
    opProps = whoami();
  } catch (_) {

    const [sessName, sessVal] = await sessionData();

    if (!!!sessName) return null;
    process.env[sessName] = sessVal;
  }

  if (opProps === null) {
    validateCli().catch((error) => {
      console.log("[ERROR] CLI is not valid:", error.message);
    });

    return getOpAuth(verbose);
  } else {
    if (verbose) console.log('[INFO] 1password login confirmed');
    const approvedVersion = read.parse('op://Employee/SECRET_TOOL/version');

    // TODO: compare current version with approved version and throw exception (?) if necessary
    /*if (verbose) */console.log('[INFO] Approved secret_tool version:', approvedVersion);
    // console.log('[INFO] Installed secret_tool version:', version);
    if (!verGreaterOrEqual(approvedVersion, version)) {
      console.log('[WARN] You need to approve version', version, 'of secret_tool in 1password to continue (https://github.com/netMedi/Holvikaari/blob/master/docs/holvikaari-dev-overview.md#installation)');
      let xyn: string | null = '';
      while (xyn === '') {
        console.log();
        console.log('Try extracting OP secrets regardless?');
        console.log('  X (or Enter) - just exit');
        console.log('  y = yes, ignore version mismatch');
        console.log('  n = no, continue without 1password');

        xyn = prompt('')?.toString()[0].toLowerCase() || '';
        switch (xyn) {
          case 'y':
            console.log('[INFO] trying to extract OP secrets...');
            break;
          case 'n':
            return null;
          default:
            if (xyn === null || 'x'.indexOf(xyn) === 0) process.exit(0);
            else {
              console.log('[ Please answer "y", "n", or "x" (single letter, no quotes) ]');
              xyn = '';
            }
        }
      }
    }

    return opProps;
  }
};

const opValueOrLiteral = (refOrValue: string, skipOpUse = false) => {
  if (refOrValue.startsWith(':::op://')) {
    if (skipOpUse) return '';
    return read.parse(refOrValue.replace(':::op://', 'op://'));
  }

  return refOrValue;
};

export default opValueOrLiteral;
