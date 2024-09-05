import { read, whoami, type ListAccount, validateCli } from "@1password/op-js";

export const getOpAuth = async (verbose = false): Promise<ListAccount | null> => {
  const sessionData = async () => {
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
    if (verbose) console.log('[INFO] Approved secret_tool version:', approvedVersion);

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
